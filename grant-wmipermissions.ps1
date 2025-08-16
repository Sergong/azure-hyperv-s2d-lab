function Set-WMINameSpaceSecurity {
    param(
        [string]$namespace,
        [string]$principal
    )

    try {
        Write-Host "Getting security object for $namespace..." -ForegroundColor Gray
        
        # Get the __SystemSecurity instance
        $security = Get-WmiObject -Namespace $namespace -Class __SystemSecurity
        
        # Create the security descriptor helper
        $converter = New-Object System.Management.ManagementClass Win32_SecurityDescriptorHelper

        # Get current security descriptor - correct parameter format
        $binarySD = @($null)
        $result = $security.PsBase.InvokeMethod("GetSD", $binarySD)
        
        if ($result -ne 0) {
            Write-Error "Failed to get Security Descriptor from $namespace (Return: $result)"
            return $false
        }

        Write-Host "Converting security descriptor..." -ForegroundColor Gray
        
        # Convert binary to SDDL
        $SDDLString = $converter.BinarySDToSDDL($binarySD[0])
        $SDDL = $SDDLString.SDDL

        Write-Host "Current SDDL length: $($SDDL.Length)" -ForegroundColor Gray

        # Get user SID
        $userSID = (New-Object System.Security.Principal.NTAccount($principal)).Translate([System.Security.Principal.SecurityIdentifier]).Value
        Write-Host "User SID: $userSID" -ForegroundColor Gray

        # Define permissions for Hyper-V management
        $WBEM_ENABLE = 1                # Enable Account
        $WBEM_METHOD_EXECUTE = 2        # Execute Methods  
        $WBEM_REMOTE_ACCESS = 32        # Remote Enable
        $READ_CONTROL = 131072          # Read Security
        
        $permissionsMask = $WBEM_ENABLE + $WBEM_METHOD_EXECUTE + $WBEM_REMOTE_ACCESS + $READ_CONTROL
        $accessMask = "0x{0:X}" -f $permissionsMask

        # Create new ACE string
        $newACE = "(A;CI;$accessMask;;;$userSID)"

        # Check if user already has permissions
        if ($SDDL -notmatch [regex]::Escape($userSID)) {
            Write-Host "Adding permissions for user..." -ForegroundColor Gray
            
            # Insert the ACE into the discretionary ACL (D: section) of SDDL
            $newSDDL = $SDDL -replace 'D:', "D:$newACE"

            Write-Host "New SDDL length: $($newSDDL.Length)" -ForegroundColor Gray

            # Convert back to binary
            $binaryNewSD = $converter.SDDLToBinarySD($newSDDL)

            # Set the new security descriptor - correct parameter format
            $binaryArray = @($binaryNewSD.BinarySD)
            $setResult = $security.PsBase.InvokeMethod("SetSD", $binaryArray)
            
            if ($setResult -eq 0) {
                Write-Host "[OK] Successfully set WMI permissions for $principal on $namespace" -ForegroundColor Green
                return $true
            } else {
                Write-Error "Failed to set permissions on $namespace (Return: $setResult)"
                return $false
            }
        } else {
            Write-Host "[OK] User $principal already has permissions on $namespace" -ForegroundColor Yellow
            return $true
        }
    } catch {
        Write-Error "Error configuring $namespace`: $($_.Exception.Message)"
        Write-Host "Error details: $($_.Exception.ToString())" -ForegroundColor Red
        return $false
    }
}

# Main execution
$username = "adm-smeeuwsen"

Write-Host "=== Setting WMI permissions for Hyper-V management ===" -ForegroundColor Cyan
Write-Host "User: $username" -ForegroundColor Yellow

# Verify user exists
try {
    $testUser = New-Object System.Security.Principal.NTAccount($username)
    $testSID = $testUser.Translate([System.Security.Principal.SecurityIdentifier])
    Write-Host "[OK] User verified: $($testSID.Value)" -ForegroundColor Green
} catch {
    Write-Error "User '$username' not found or cannot be resolved"
    exit 1
}

# Set permissions on required WMI namespaces for Hyper-V
$namespaces = @("root/interop", "root/cimv2", "root/default")
$allSuccess = $true

foreach ($namespace in $namespaces) {
    Write-Host "`n--- Configuring permissions for $username on $namespace ---" -ForegroundColor Yellow
    $success = Set-WMINameSpaceSecurity -namespace $namespace -principal $username
    $allSuccess = $allSuccess -and $success
}

if ($allSuccess) {
    Write-Host "`n=== Restarting WMI service to apply changes ===" -ForegroundColor Cyan
    try {
        Restart-Service -Name "Winmgmt" -Force
        Start-Sleep -Seconds 3
        Write-Host "[OK] WMI service restarted successfully" -ForegroundColor Green
        Write-Host "`n=== WMI permissions configuration completed successfully! ===" -ForegroundColor Green
        Write-Host "You can now try connecting with Hyper-V Manager" -ForegroundColor Cyan
    } catch {
        Write-Warning "Failed to restart WMI service: $($_.Exception.Message)"
        Write-Host "Please manually restart the 'Windows Management Instrumentation' service" -ForegroundColor Yellow
    }
} else {
    Write-Warning "Some WMI namespace configurations failed. Please check the errors above."
    Write-Host "You may need to use the GUI method (wmimgmt.msc) instead" -ForegroundColor Yellow
}

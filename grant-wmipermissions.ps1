function Set-WMINameSpaceSecurity {
    param(
        [string]$namespace,
        [string]$principal
    )

    try {
        # Get the __SystemSecurity instance
        $security = Get-WmiObject -Namespace $namespace -Class __SystemSecurity

        # Prepare the converter for SDDL <-> Binary conversion
        $converter = New-Object System.Management.ManagementClass Win32_SecurityDescriptorHelper

        # Get current security descriptor (binary) using GetSD method (not GetSecurityDescriptor)
        $result = $security.PsBase.InvokeMethod("GetSD", $null)
        if ($result.ReturnValue -ne 0) {
            Write-Error "Failed to get Security Descriptor from $namespace (Return: $($result.ReturnValue))"
            return $false
        }

        $binarySD = $result.Descriptor

        # Convert binary to SDDL
        $SDDLString = $converter.BinarySDToSDDL($binarySD)
        $SDDL = $SDDLString.SDDL

        # Get user SID
        $userSID = (New-Object System.Security.Principal.NTAccount($principal)).Translate([System.Security.Principal.SecurityIdentifier]).Value

        # Define permissions: Enable (1), Remote Enable(32), Execute(2), Read Control (131072)
        $WBEM_ENABLE = 1
        $WBEM_REMOTE_ACCESS = 32
        $WBEM_METHOD_EXECUTE = 2
        $READ_CONTROL = 131072
        $permissionsMask = $WBEM_ENABLE + $WBEM_REMOTE_ACCESS + $WBEM_METHOD_EXECUTE + $READ_CONTROL
        $accessMask = "0x{0:X}" -f $permissionsMask

        # Prepare new ACE string
        $newACE = "(A;CI;$accessMask;;;$userSID)"

        # Check if user already has permissions
        if ($SDDL -notmatch $userSID) {
            # Insert the ACE into the discretionary ACL (D: section) of SDDL
            $newSDDL = $SDDL -replace 'D:', "D:$newACE"

            # Convert back to binary
            $binaryNewSD = $converter.SDDLToBinarySD($newSDDL)

            # Set the new security descriptor using SetSD method (not SetSecurityDescriptor)
            $setResult = $security.PsBase.InvokeMethod("SetSD", @($binaryNewSD.BinarySD))
            if ($setResult.ReturnValue -eq 0) {
                Write-Host "[OK] Successfully set WMI permissions for $principal on $namespace" -ForegroundColor Green
                return $true
            } else {
                Write-Error "Failed to set permissions on $namespace (Return: $($setResult.ReturnValue))"
                return $false
            }
        } else {
            Write-Host "[OK] User $principal already has permissions on $namespace" -ForegroundColor Yellow
            return $true
        }
    } catch {
        Write-Error "Error configuring $namespace`: $($_.Exception.Message)"
        return $false
    }
}

# Main execution
$username = "adm-smeeuwsen"  # Your actual username

Write-Host "=== Setting WMI permissions for Hyper-V management ===" -ForegroundColor Cyan
Write-Host "User: $username" -ForegroundColor Yellow

# Set permissions on required WMI namespaces for Hyper-V
$namespaces = @("root/interop", "root/cimv2", "root/default")
$allSuccess = $true

foreach ($namespace in $namespaces) {
    Write-Host "`nConfiguring permissions for $username on $namespace..." -ForegroundColor Yellow
    $success = Set-WMINameSpaceSecurity -namespace $namespace -principal $username
    $allSuccess = $allSuccess -and $success
}

if ($allSuccess) {
    Write-Host "`n=== Restarting WMI service to apply changes ===" -ForegroundColor Cyan
    try {
        Restart-Service -Name "Winmgmt" -Force
        Write-Host "[OK] WMI service restarted successfully" -ForegroundColor Green
        Write-Host "`n=== WMI permissions configuration completed successfully! ===" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to restart WMI service: $($_.Exception.Message)"
        Write-Host "Please manually restart the 'Windows Management Instrumentation' service" -ForegroundColor Yellow
    }
} else {
    Write-Warning "Some WMI namespace configurations failed. Please check the errors above."
}

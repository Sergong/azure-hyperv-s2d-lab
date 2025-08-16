# Run this script as Administrator on hyperv-node-1

function Set-WMINameSpaceSecurity {
    param(
        [string]$namespace,
        [string]$principal
    )
    
    $ErrorActionPreference = "Stop"
    
    try {
        # Get the security descriptor for the WMI namespace
        $security = Get-WmiObject -Namespace $namespace -Class "__SystemSecurity"
        $binarySD = $security.GetSecurityDescriptor().Descriptor
        
        # Convert binary security descriptor to SDDL format
        $converter = New-Object System.Management.ManagementClass Win32_SecurityDescriptorHelper
        $stringSD = $converter.BinarySDToSDDL($binarySD)
        $SDDL = $stringSD.SDDL
        
        # Define only the access rights we actually need for Hyper-V management
        $WBEM_ENABLE = 1           # Enable Account
        $WBEM_METHOD_EXECUTE = 2   # Execute Methods  
        $WBEM_REMOTE_ACCESS = 32   # Remote Enable
        $READ_CONTROL = 131072     # Read Security
        
        # Calculate permissions needed for Hyper-V management
        $permissionMask = $WBEM_ENABLE + $WBEM_METHOD_EXECUTE + $WBEM_REMOTE_ACCESS + $READ_CONTROL
        
        # Get user SID
        $userSID = (New-Object System.Security.Principal.NTAccount($principal)).Translate([System.Security.Principal.SecurityIdentifier]).Value
        
        # Build new ACE (Access Control Entry) - using the variables properly
        $accessMask = "0x{0:X}" -f $permissionMask
        $newACE = "(A;CI;$accessMask;;;$userSID)"
        
        # Add the new ACE to the SDDL if user doesn't already have permissions
        if ($SDDL -notlike "*$userSID*") {
            $newSDDL = $SDDL.Replace("S:", "$newACE" + "S:")
            
            # Convert back to binary and set
            $binarySDNew = $converter.SDDLToBinarySD($newSDDL)
            $result = $security.SetSecurityDescriptor($binarySDNew.BinarySD)
            
            if ($result.ReturnValue -eq 0) {
                Write-Host "[OK] Successfully set WMI permissions for $principal on $namespace" -ForegroundColor Green
                return $true
            } else {
                Write-Warning "Failed to set WMI permissions on $namespace. Return value: $($result.ReturnValue)"
                return $false
            }
        } else {
            Write-Host "[OK] User $principal already has permissions on $namespace" -ForegroundColor Yellow
            return $true
        }
    } catch {
        Write-Error "Error setting WMI permissions on $namespace`: $($_.Exception.Message)"
        return $false
    }
}

# Main execution
$username = "adm-smeeuwsen"  # Replace with actual username

Write-Host "=== Setting WMI permissions for Hyper-V management ===" -ForegroundColor Cyan
Write-Host "User: $username" -ForegroundColor Yellow

# Set permissions on required WMI namespaces for Hyper-V
$namespaces = @("root/interop", "root/cimv2", "root/default")
$allSuccess = $true

foreach ($namespace in $namespaces) {
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

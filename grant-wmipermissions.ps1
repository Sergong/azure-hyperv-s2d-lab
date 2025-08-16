function Grant-WMIPermissions {
    param(
        [string]$Username,
        [string[]]$Namespaces = @("root/interop", "root/cimv2", "root/default")
    )
    
    # Get user SID
    $user = New-Object System.Security.Principal.NTAccount($Username)
    $sid = $user.Translate([System.Security.Principal.SecurityIdentifier])
    
    foreach ($namespace in $Namespaces) {
        Write-Host "Configuring permissions for $Username on $namespace..." -ForegroundColor Yellow
        
        try {
            # Get current security settings
            $security = Get-WmiObject -Namespace $namespace -Class __SystemSecurity
            
            # Get current security descriptor
            $currentSD = $security.GetSecurityDescriptor()
            
            # Create new ACE for the user
            $ace = ([WMIClass] "$namespace`:__ace").CreateInstance()
            $ace.AccessMask = 33  # Enable + Remote Enable
            $ace.AceFlags = 2     # Container Inherit
            $ace.AceType = 0      # Allow
            $trustee = ([WMIClass] "$namespace`:__trustee").CreateInstance()
            $trustee.SidString = $sid.Value
            $ace.Trustee = $trustee
            
            # Add ACE to security descriptor
            $currentSD.Descriptor.DACL += $ace.PSObject.BaseObject
            
            # Apply new security descriptor
            $result = $security.SetSecurityDescriptor($currentSD.Descriptor)
            
            if ($result.ReturnValue -eq 0) {
                Write-Host "[OK] Successfully configured $namespace" -ForegroundColor Green
            } else {
                Write-Warning "Failed to configure $namespace (Return code: $($result.ReturnValue))"
            }
        } catch {
            Write-Warning "Error configuring $namespace`: $($_.Exception.Message)"
        }
    }
    
    # Restart WMI service
    Write-Host "Restarting WMI service..." -ForegroundColor Yellow
    Restart-Service Winmgmt -Force
    Write-Host "WMI permissions configuration completed!" -ForegroundColor Green
}

# Usage - replace with your actual username
Grant-WMIPermissions -Username "adm-smeeuwsen"
# Standalone WinRM Configuration Script for Workgroup Environments
# This script configures WinRM for PowerShell Remoting between workgroup computers
# Run this script on both hyperv-node-0 and hyperv-node-1

param(
    [string[]]$TrustedHosts = @("hyperv-node-0", "hyperv-node-1", "10.0.1.*", "192.168.*", "localhost", "127.0.0.1")
)

# Ensure running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator. Exiting."
    exit 1
}

# Start logging
Start-Transcript -Path "C:\WinRM-Configuration-Log.txt" -Append

Write-Host "==========================================="
Write-Host "WinRM Configuration for Workgroup"
Write-Host "==========================================="
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "Date: $(Get-Date)"
Write-Host "Trusted Hosts: $($TrustedHosts -join ', ')"
Write-Host "==========================================="

try {
    # Check and start WinRM service
    Write-Host "Configuring WinRM service..."
    
    $winrmService = Get-Service -Name WinRM
    Write-Host "Current WinRM service status: $($winrmService.Status)"
    
    # Set service to automatic startup
    Set-Service -Name WinRM -StartupType Automatic
    
    # Start the service if not running
    if ($winrmService.Status -ne 'Running') {
        Start-Service -Name WinRM
        Write-Host "Started WinRM service"
    } else {
        Write-Host "WinRM service already running"
    }
    
    # Enable PowerShell Remoting
    Write-Host "Enabling PowerShell Remoting..."
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    Write-Host "PowerShell Remoting enabled"
    
    # Configure WinRM authentication for workgroup
    Write-Host "Configuring WinRM authentication settings..."
    
    # Enable basic authentication (required for workgroup)
    winrm set winrm/config/service/auth '@{Basic="true"}'
    winrm set winrm/config/client/auth '@{Basic="true"}'
    Write-Host "Enabled basic authentication"
    
    # Allow unencrypted traffic (workgroup requirement)
    winrm set winrm/config/service '@{AllowUnencrypted="true"}'
    winrm set winrm/config/client '@{AllowUnencrypted="true"}'
    Write-Host "Enabled unencrypted traffic (workgroup mode)"
    
    # Configure trusted hosts
    $trustedHostsList = $TrustedHosts -join ","
    Write-Host "Setting trusted hosts: $trustedHostsList"
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value $trustedHostsList -Force
    Write-Host "Trusted hosts configured"
    
    # Increase limits for cluster operations
    Write-Host "Configuring WinRM limits for cluster operations..."
    winrm set winrm/config '@{MaxEnvelopeSizekb="2048"}'
    winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="2048"}'
    winrm set winrm/config/winrs '@{MaxShellsPerUser="50"}'
    winrm set winrm/config/winrs '@{MaxConcurrentUsers="100"}'
    Write-Host "WinRM limits configured"
    
    # Configure Windows Firewall
    Write-Host "Configuring Windows Firewall for WinRM..."
    
    # Enable built-in WinRM firewall rules
    Enable-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)" -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayName "Windows Remote Management (HTTPS-In)" -ErrorAction SilentlyContinue
    
    # Create custom firewall rules for workgroup
    try {
        $existingHTTP = Get-NetFirewallRule -DisplayName "WinRM-HTTP-Workgroup" -ErrorAction SilentlyContinue
        if (-not $existingHTTP) {
            New-NetFirewallRule -DisplayName "WinRM-HTTP-Workgroup" -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any
            Write-Host "Created WinRM HTTP firewall rule"
        }
        
        $existingHTTPS = Get-NetFirewallRule -DisplayName "WinRM-HTTPS-Workgroup" -ErrorAction SilentlyContinue
        if (-not $existingHTTPS) {
            New-NetFirewallRule -DisplayName "WinRM-HTTPS-Workgroup" -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow -Profile Any
            Write-Host "Created WinRM HTTPS firewall rule"
        }
    } catch {
        Write-Warning "Could not create custom firewall rules: $($_.Exception.Message)"
    }
    
    # Configure registry settings for workgroup remoting
    Write-Host "Configuring registry settings for workgroup remoting..."
    
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    
    # LocalAccountTokenFilterPolicy - enables remote connections with local accounts
    Set-ItemProperty -Path $regPath -Name "LocalAccountTokenFilterPolicy" -Value 1 -Type DWord -Force
    Write-Host "Set LocalAccountTokenFilterPolicy to 1"
    
    # FilterAdministratorToken - disable UAC filtering for built-in administrator
    Set-ItemProperty -Path $regPath -Name "FilterAdministratorToken" -Value 0 -Type DWord -Force
    Write-Host "Set FilterAdministratorToken to 0"
    
    # Configure network profile
    Write-Host "Configuring network profiles..."
    try {
        $profiles = Get-NetConnectionProfile
        foreach ($profile in $profiles) {
            if ($profile.NetworkCategory -ne 'Private') {
                Set-NetConnectionProfile -InterfaceIndex $profile.InterfaceIndex -NetworkCategory Private
                Write-Host "Set network profile '$($profile.Name)' to Private"
            }
        }
    } catch {
        Write-Warning "Could not set network profile: $($_.Exception.Message)"
    }
    
    # Restart WinRM service to apply all changes
    Write-Host "Restarting WinRM service to apply configuration..."
    Restart-Service -Name WinRM -Force
    Start-Sleep -Seconds 3
    
    # Display final configuration
    Write-Host ""
    Write-Host "==========================================="
    Write-Host "WINRM CONFIGURATION COMPLETE!"
    Write-Host "==========================================="
    
    # Show WinRM configuration
    Write-Host "Current WinRM Configuration:"
    Write-Host ""
    
    $config = winrm get winrm/config
    Write-Host "WinRM Service Status: $((Get-Service -Name WinRM).Status)"
    
    $trustedHosts = Get-Item WSMan:\localhost\Client\TrustedHosts
    Write-Host "Trusted Hosts: $($trustedHosts.Value)"
    
    $authConfig = winrm get winrm/config/service/auth
    Write-Host "Authentication Configuration Applied"
    
    Write-Host ""
    Write-Host "PowerShell Remoting Test Commands:"
    Write-Host "  Test-WSMan hyperv-node-0"
    Write-Host "  Test-WSMan hyperv-node-1"
    Write-Host "  Invoke-Command -ComputerName hyperv-node-0 -ScriptBlock { Get-ComputerInfo } -Credential (Get-Credential)"
    Write-Host ""
    Write-Host "For clustering, use credentials like: .\Administrator or COMPUTERNAME\Administrator"
    
} catch {
    Write-Error "WinRM configuration failed: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "Manual configuration commands:"
    Write-Host "  Enable-PSRemoting -Force"
    Write-Host "  Set-Item WSMan:\localhost\Client\TrustedHosts -Value 'hyperv-node-0,hyperv-node-1,10.0.1.*' -Force"
    Write-Host "  winrm set winrm/config/service/auth '@{Basic=\"true\"}'"
    Write-Host "  winrm set winrm/config/client/auth '@{Basic=\"true\"}'"
    Write-Host "  winrm set winrm/config/service '@{AllowUnencrypted=\"true\"}'"
    Write-Host "  Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'LocalAccountTokenFilterPolicy' -Value 1 -Type DWord"
    
    Stop-Transcript
    exit 1
}

Write-Host ""
Write-Host "Configuration log saved to: C:\WinRM-Configuration-Log.txt"
Stop-Transcript

Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Run this script on both nodes

# Create self-signed certificate
$cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My

# Create HTTPS listener
winrm create winrm/config/Listener?Address=*+Transport=HTTPS "@{Hostname=`"$env:COMPUTERNAME`";CertificateThumbprint=`"$($cert.Thumbprint)`"}"

# Configure firewall
New-NetFirewallRule -DisplayName "WinRM HTTPS" -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow

# On both nodes - enable CredSSP delegation
Enable-WSManCredSSP -Role Server -Force
Enable-WSManCredSSP -Role Client -DelegateComputer "*" -Force

# Enable Enhanced Session Mode on both hosts This often provides better cross-node console connectivity
Set-VMHost -EnableEnhancedSessionMode $true

write-host "========== run the following manually! ==========="
write-host "`n# Configure policy (run gpedit.msc as admin)"
write-host "# Navigate to: Computer Configuration > Administrative Templates > System > Credentials Delegation"
write-host "# Enable: 'Allow delegating fresh credentials'"
write-host "# Add: 'WSMAN/*'"

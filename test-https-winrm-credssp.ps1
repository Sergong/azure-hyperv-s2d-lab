# Test HTTPS listener
winrm enumerate winrm/config/listener

# From hyperv-node-0 to hyperv-node-1
Test-WSMan -ComputerName hyperv-node-1 -UseSSL

# Test PowerShell remoting over HTTPS
Enter-PSSession -ComputerName hyperv-node-1 -UseSSL -Credential (Get-Credential)


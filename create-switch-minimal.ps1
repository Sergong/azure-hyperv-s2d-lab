# Ultra-simple virtual switch creation script
# Just creates the InternalLabSwitch with minimal error handling

Write-Host "Creating InternalLabSwitch virtual switch..."

try {
    # Check if switch exists
    $switch = Get-VMSwitch -Name "InternalLabSwitch" -ErrorAction SilentlyContinue
    
    if ($switch) {
        Write-Host "Switch already exists"
    } else {
        # Create the switch
        New-VMSwitch -Name "InternalLabSwitch" -SwitchType Internal | Out-Null
        Write-Host "Switch created"
        
        # Configure IP
        Start-Sleep -Seconds 2
        $adapter = Get-NetAdapter -Name "vEthernet (InternalLabSwitch)"
        New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -IPAddress "192.168.100.1" -PrefixLength 24 | Out-Null
        Write-Host "IP configured: 192.168.100.1/24"
    }
    
    Write-Host "Setup complete!"
    
} catch {
    Write-Host "Error: $($_.Exception.Message)"
}

Write-Host "Press Enter to exit..."
Read-Host

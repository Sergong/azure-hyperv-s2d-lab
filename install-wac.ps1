# Download WAC installer
$parameters = @{
    Source = "https://aka.ms/WACdownload"
    Destination = ".\WindowsAdminCenter.exe"
}
Start-BitsTransfer @parameters

# Install silently
Start-Process -FilePath '.\WindowsAdminCenter.exe' -ArgumentList '/VERYSILENT' -Wait

# Start the service (if needed)
Start-Service -Name WindowsAdminCenter

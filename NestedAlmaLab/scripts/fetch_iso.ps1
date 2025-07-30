# Download latest AlmaLinux ISO
$isoUrl = "https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9-latest-x86_64.iso"
$isoDest = "C:\ISOs\AlmaLinux-latest-x86_64.iso"

Invoke-WebRequest -Uri $isoUrl -OutFile $isoDest -UseBasicParsing
Write-Host "✅ ISO downloaded to $isoDest"

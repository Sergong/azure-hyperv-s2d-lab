# Download latest AlmaLinux ISO
$isoUrl = "https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9-latest-x86_64-dvd.iso"
$isoPath = "C:\ISOs"
$isoDest = "$isoPath\AlmaLinux-latest-x86_64.iso"

if (!(Test-Path $isoPath)){
    mkdir $isoPath
}

$dlResult = Invoke-WebRequest -Uri $isoUrl -OutFile $isoDest -UseBasicParsing -ErrorAction SilentlyContinue
if ($dlResult){
    Write-Host "✅ ISO downloaded to $isoDest"
} else {
    write-host "Error with downloading occurred!"
}

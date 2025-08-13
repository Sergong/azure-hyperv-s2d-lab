# Script to manually download the S2D setup script (FIXED VERSION)
# Run this on hyperv-node-0 if the automatic download failed
# This downloads the corrected version with PowerShell syntax errors fixed

$S2DScriptUrl = "https://hypervscriptsjdlf6gwh.blob.core.windows.net/scripts/setup-s2d-cluster.ps1"
$OutputPath = "C:\setup-s2d-cluster.ps1"

Write-Host "Downloading S2D setup script from blob storage..."
Write-Host "Source: $S2DScriptUrl"
Write-Host "Destination: $OutputPath"

try {
    # Download the script
    Invoke-WebRequest -Uri $S2DScriptUrl -OutFile $OutputPath -UseBasicParsing
    
    # Verify the file was downloaded
    if (Test-Path $OutputPath) {
        $fileInfo = Get-Item $OutputPath
        Write-Host "SUCCESS: S2D script downloaded successfully!"
        Write-Host "File size: $($fileInfo.Length) bytes"
        Write-Host "Created: $($fileInfo.CreationTime)"
        Write-Host ""
        Write-Host "You can now run the S2D setup script with:"
        Write-Host "PowerShell -ExecutionPolicy Bypass -File C:\setup-s2d-cluster.ps1"
    } else {
        Write-Host "ERROR: File was not created at $OutputPath"
    }
} catch {
    Write-Host "ERROR: Failed to download S2D script: $($_.Exception.Message)"
    Write-Host "Please check network connectivity and try again."
}

# Also show current directory contents for reference
Write-Host ""
Write-Host "Current C:\ directory contents:"
Get-ChildItem C:\ -Filter "*.ps1" | Format-Table Name, Length, LastWriteTime -AutoSize

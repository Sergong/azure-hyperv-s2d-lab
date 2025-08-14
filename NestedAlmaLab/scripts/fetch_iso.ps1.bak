# AlmaLinux ISO Download Script with Multiple Methods
# This script provides several options for downloading AlmaLinux ISO

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("manual", "curl", "wget", "bitsadmin", "powershell")]
    [string]$Method = "manual",
    
    [Parameter(Mandatory=$false)]
    [string]$IsoVersion = "9",
    
    [Parameter(Mandatory=$false)]
    [string]$IsoPath = "C:\ISOs"
)

# ISO URLs and information
$isoUrls = @{
    "9" = @{
        "dvd" = "https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9-latest-x86_64-dvd.iso"
        "minimal" = "https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9-latest-x86_64-minimal.iso"
        "boot" = "https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9-latest-x86_64-boot.iso"
    }
    "8" = @{
        "dvd" = "https://repo.almalinux.org/almalinux/8/isos/x86_64/AlmaLinux-8-latest-x86_64-dvd.iso"
        "minimal" = "https://repo.almalinux.org/almalinux/8/isos/x86_64/AlmaLinux-8-latest-x86_64-minimal.iso"
        "boot" = "https://repo.almalinux.org/almalinux/8/isos/x86_64/AlmaLinux-8-latest-x86_64-boot.iso"
    }
}

$isoUrl = $isoUrls[$IsoVersion]["dvd"]  # Default to DVD version
$isoFileName = "AlmaLinux-$IsoVersion-latest-x86_64.iso"
$isoDest = Join-Path $IsoPath $isoFileName

# Create ISO directory if it doesn't exist
if (!(Test-Path $IsoPath)) {
    Write-Host "Creating ISO directory: $IsoPath"
    New-Item -ItemType Directory -Path $IsoPath -Force | Out-Null
}

Write-Host "==========================================="
Write-Host "AlmaLinux ISO Download Script"
Write-Host "==========================================="
Write-Host "ISO Version: AlmaLinux $IsoVersion"
Write-Host "Download URL: $isoUrl"
Write-Host "Destination: $isoDest"
Write-Host "Method: $Method"
Write-Host "==========================================="

# Check if ISO already exists
if (Test-Path $isoDest) {
    $fileSize = (Get-Item $isoDest).Length / 1GB
    Write-Host "⚠️  ISO file already exists: $isoDest ($([math]::Round($fileSize, 2)) GB)"
    $overwrite = Read-Host "Do you want to overwrite it? (y/N)"
    if ($overwrite -ne 'y' -and $overwrite -ne 'Y') {
        Write-Host "✅ Using existing ISO file"
        exit 0
    }
}

switch ($Method) {
    "manual" {
        Write-Host "`n🚀 RECOMMENDED: Manual Download"
        Write-Host "==========================================="
        Write-Host "For the fastest and most reliable download, please:"
        Write-Host ""
        Write-Host "1. Open your web browser (Edge, Chrome, Firefox)"
        Write-Host "2. Navigate to: $isoUrl"
        Write-Host "3. Save the file to: $isoDest"
        Write-Host ""
        Write-Host "Alternative mirror sites (may be faster):"
        Write-Host "- https://mirrors.almalinux.org/isos.html"
        Write-Host "- Choose a mirror closest to your location"
        Write-Host ""
        Write-Host "Expected file size: ~9-10 GB (DVD version)"
        Write-Host "Download time: 10-30 minutes (depending on connection)"
        Write-Host ""
        Write-Host "✨ Browser downloads are typically 5-10x faster than PowerShell!"
        Write-Host "==========================================="
        
        # Open the URL in default browser
        $openBrowser = Read-Host "Open download URL in browser now? (Y/n)"
        if ($openBrowser -ne 'n' -and $openBrowser -ne 'N') {
            Start-Process $isoUrl
            Write-Host "✅ Opened download URL in default browser"
        }
        
        # Open destination folder
        $openFolder = Read-Host "Open destination folder? (Y/n)"
        if ($openFolder -ne 'n' -and $openFolder -ne 'N') {
            Invoke-Item $IsoPath
            Write-Host "✅ Opened destination folder: $IsoPath"
        }
    }
    
    "curl" {
        Write-Host "`n📥 Downloading with curl..."
        if (Get-Command curl -ErrorAction SilentlyContinue) {
            Write-Host "Starting download with curl (this may take 15-45 minutes)..."
            $curlArgs = @(
                "-L",                    # Follow redirects
                "-o", $isoDest,         # Output file
                "--progress-bar",       # Show progress
                "--fail",               # Fail on HTTP errors
                "--retry", "3",         # Retry on failure
                "--retry-delay", "5",   # Delay between retries
                "--connect-timeout", "30", # Connection timeout
                "--max-time", "3600",   # Max time (1 hour)
                $isoUrl
            )
            
            try {
                & curl $curlArgs
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ ISO downloaded successfully with curl"
                } else {
                    throw "Curl failed with exit code: $LASTEXITCODE"
                }
            } catch {
                Write-Host "❌ Curl download failed: $($_.Exception.Message)"
                Write-Host "💡 Try the 'manual' method for better reliability"
                exit 1
            }
        } else {
            Write-Host "❌ curl is not available on this system"
            Write-Host "💡 Try the 'manual' method instead"
            exit 1
        }
    }
    
    "wget" {
        Write-Host "`n📥 Downloading with wget..."
        if (Get-Command wget -ErrorAction SilentlyContinue) {
            Write-Host "Starting download with wget (this may take 15-45 minutes)..."
            try {
                & wget $isoUrl -O $isoDest --progress=bar --tries=3 --timeout=30
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ ISO downloaded successfully with wget"
                } else {
                    throw "Wget failed with exit code: $LASTEXITCODE"
                }
            } catch {
                Write-Host "❌ Wget download failed: $($_.Exception.Message)"
                Write-Host "💡 Try the 'manual' method for better reliability"
                exit 1
            }
        } else {
            Write-Host "❌ wget is not available on this system"
            Write-Host "💡 Install wget or try the 'manual' method"
            exit 1
        }
    }
    
    "bitsadmin" {
        Write-Host "`n📥 Downloading with BITS (Background Intelligent Transfer Service)..."
        Write-Host "Starting download with bitsadmin (this may take 15-45 minutes)..."
        try {
            $jobName = "AlmaLinuxISO-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            & bitsadmin /create $jobName
            & bitsadmin /addfile $jobName $isoUrl $isoDest
            & bitsadmin /resume $jobName
            
            # Monitor progress
            Write-Host "Download started. Monitoring progress..."
            do {
                $status = & bitsadmin /info $jobName /verbose
                if ($status -match "STATE: TRANSFERRED") {
                    & bitsadmin /complete $jobName
                    Write-Host "✅ ISO downloaded successfully with BITS"
                    break
                }
                elseif ($status -match "STATE: ERROR") {
                    throw "BITS transfer failed"
                }
                Start-Sleep -Seconds 10
                Write-Host "."
            } while ($true)
        } catch {
            Write-Host "❌ BITS download failed: $($_.Exception.Message)"
            Write-Host "💡 Try the 'manual' method for better reliability"
            # Clean up failed job
            & bitsadmin /cancel $jobName 2>$null
            exit 1
        }
    }
    
    "powershell" {
        Write-Host "`n📥 Downloading with PowerShell (Invoke-WebRequest)..."
        Write-Host "⚠️  WARNING: This method is slow and may fail for large files!"
        Write-Host "💡 Consider using 'manual' method instead for better reliability"
        
        $continue = Read-Host "Continue with PowerShell download anyway? (y/N)"
        if ($continue -ne 'y' -and $continue -ne 'Y') {
            Write-Host "Download cancelled. Use -Method manual for best results."
            exit 0
        }
        
        Write-Host "Starting download with Invoke-WebRequest (this may take 30-60 minutes or fail)..."
        try {
            # Use System.Net.WebClient for better performance than Invoke-WebRequest
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($isoUrl, $isoDest)
            Write-Host "✅ ISO downloaded successfully with PowerShell"
        } catch {
            Write-Host "❌ PowerShell download failed: $($_.Exception.Message)"
            Write-Host "💡 Try the 'manual' method for better reliability"
            exit 1
        }
    }
}

# Verify download
if (Test-Path $isoDest) {
    $fileSize = (Get-Item $isoDest).Length
    $fileSizeGB = [math]::Round($fileSize / 1GB, 2)
    
    Write-Host "`n==========================================="
    Write-Host "Download Summary"
    Write-Host "==========================================="
    Write-Host "✅ File: $isoDest"
    Write-Host "✅ Size: $fileSizeGB GB ($fileSize bytes)"
    Write-Host "✅ Method: $Method"
    
    # Basic size validation (AlmaLinux DVD should be 8-12 GB)
    if ($fileSize -lt 1GB) {
        Write-Host "⚠️  WARNING: File size seems too small. Download may be incomplete."
    } elseif ($fileSize -gt 15GB) {
        Write-Host "⚠️  WARNING: File size seems too large. Please verify the download."
    } else {
        Write-Host "✅ File size looks reasonable for AlmaLinux DVD ISO"
    }
    
    Write-Host "==========================================="
    Write-Host "✅ ISO ready for VM provisioning!"
} else {
    Write-Host "❌ Download failed - ISO file not found"
    exit 1
}

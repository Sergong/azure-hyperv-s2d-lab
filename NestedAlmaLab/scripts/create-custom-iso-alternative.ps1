# Alternative AlmaLinux Custom ISO Creator
# This version uses a more conservative approach to avoid checksum issues
#
# Uses minimal modification approach - only modifies boot config, preserves original ISO structure

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("v1", "v2")]
    [string]$KickstartVersion = "v1",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet(1, 2)]
    [int]$Generation = 1
)

# Load configuration
$configPath = Join-Path $PSScriptRoot "config.yaml"
if (-not (Test-Path $configPath)) {
    Write-Error "Configuration file not found: $configPath"
    exit 1
}

# Simple YAML parser
function ConvertFrom-Yaml {
    param([string]$YamlContent)
    $config = @{}
    $lines = $YamlContent -split "`n" | Where-Object { $_ -match '^\s*\w+:' }
    foreach ($line in $lines) {
        if ($line -match '^\s*([^:]+):\s*"?([^"]+)"?\s*$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim().Trim('"')
            $config[$key] = $value
        }
    }
    return $config
}

$yamlContent = Get-Content $configPath -Raw
$config = ConvertFrom-Yaml -YamlContent $yamlContent

# Configuration
$originalISO = $config["iso_path"]
$outputDir = Join-Path (Split-Path $PSScriptRoot) "custom-iso"
$customISOName = "AlmaLinux-$KickstartVersion-Gen$Generation-Safe.iso"
$customISO = Join-Path $outputDir $customISOName
$workDir = Join-Path $env:USERPROFILE "alma-iso-safe-$(Get-Random)"
$extractDir = Join-Path $workDir "extracted"
$kickstartFile = Join-Path $PSScriptRoot "..\templates\AlmaLinux\$KickstartVersion\ks.cfg"

Write-Host "=== AlmaLinux Safe Custom ISO Creator ===" -ForegroundColor Cyan
Write-Host "This version uses a conservative approach to avoid checksum errors"
Write-Host "Original ISO: $originalISO"
Write-Host "Output: $customISO"
Write-Host ""

# Validate inputs
if (-not (Test-Path $originalISO)) {
    Write-Error "Original AlmaLinux ISO not found: $originalISO"
    exit 1
}

if (-not (Test-Path $kickstartFile)) {
    Write-Error "Kickstart file not found: $kickstartFile"
    exit 1
}

# Try to find a suitable ISO creation tool (in order of preference)
$isoTool = $null
$isoMethod = $null

# Method 1: Try PowerISO first (commercial tool - most reliable)
$powerISOPath = "${env:ProgramFiles}\PowerISO\piso.exe"
if (Test-Path $powerISOPath) {
    $isoTool = $powerISOPath
    $isoMethod = "poweriso"
    Write-Host "Found PowerISO - using preferred tool"
}

# Method 2: Try cdrtfe (free tool - good alternative)
if (-not $isoTool) {
    $cdrPath = "${env:ProgramFiles}\cdrtfe\cdrtfe.exe"
    if (Test-Path $cdrPath) {
        $isoTool = $cdrPath
        $isoMethod = "cdrtfe"
        Write-Host "Found cdrtfe - using free alternative"
    }
}

# Method 3: Fallback to oscdimg (Windows ADK - can be problematic)
if (-not $isoTool) {
    $oscdimgPath = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    if (Test-Path $oscdimgPath) {
        $isoTool = $oscdimgPath
        $isoMethod = "oscdimg_basic"
        Write-Host "Found oscdimg.exe - using as fallback (may have checksum issues)"
    }
}

if (-not $isoTool) {
    Write-Error "No suitable ISO creation tool found."
    Write-Host "Please install one of the following:"
    Write-Host "1. Windows ADK (recommended, free)"
    Write-Host "2. PowerISO (commercial)"
    Write-Host "3. Any other ISO creation tool"
    exit 1
}

try {
    # Clean up previous work
    if (Test-Path $workDir) {
        Remove-Item $workDir -Recurse -Force
    }
    if (Test-Path $customISO) {
        Remove-Item $customISO -Force
    }
    
    # Create directories
    New-Item -ItemType Directory -Path $outputDir, $workDir, $extractDir -Force | Out-Null
    
    Write-Host "Step 1: Extracting original ISO..."
    # Use 7-Zip if available for better extraction
    $sevenZipPath = "${env:ProgramFiles}\7-Zip\7z.exe"
    if (Test-Path $sevenZipPath) {
        Write-Host "  Using 7-Zip for extraction"
        & $sevenZipPath x "$originalISO" -o"$extractDir" -y | Out-Null
    } else {
        # Fallback to mount/copy
        Write-Host "  Using mount/copy method"
        $mountResult = Mount-DiskImage -ImagePath $originalISO -PassThru
        $driveLetter = ($mountResult | Get-Volume).DriveLetter
        robocopy "${driveLetter}:\" $extractDir /E /NP /NJH /NJS | Out-Null
        Dismount-DiskImage -ImagePath $originalISO
    }
    
    Write-Host "Step 2: Removing read-only attributes..."
    # Use simple attrib command - most reliable method
    cmd /c "attrib -R `"$extractDir\*.*`" /S /D" | Out-Null
    
    Write-Host "Step 3: Adding kickstart file..."
    Copy-Item $kickstartFile "$extractDir\ks.cfg" -Force
    
    Write-Host "Step 4: Modifying boot configuration (minimal changes)..."
    $bootParams = "inst.ks=cdrom:/ks.cfg inst.text console=tty0 console=ttyS0,115200"
    
    # Only modify the primary boot configuration file
    $isolinuxCfg = "$extractDir\isolinux\isolinux.cfg"
    if (Test-Path $isolinuxCfg) {
        Write-Host "  Modifying isolinux.cfg"
        $content = Get-Content $isolinuxCfg -Raw
        
        # Simple replacement - find first append line and add parameters
        if ($content -match "(append\s+[^\r\n]+)") {
            $newContent = $content -replace "(append\s+[^\r\n]+)", "`$1 $bootParams"
            Set-Content $isolinuxCfg $newContent -NoNewline
            Write-Host "    Added kickstart parameters to boot configuration"
        } else {
            Write-Warning "    Could not find append line in isolinux.cfg"
        }
    }
    
    Write-Host "Step 5: Creating ISO with minimal processing..."
    
    switch ($isoMethod) {
        "oscdimg_basic" {
            # Use absolute minimal oscdimg parameters
            $oscdimgArgs = @(
                "-m"                           # Ignore max size limit
                "-b`"${extractDir}\isolinux\isolinux.bin`""  # Boot sector
            )
            
            # Only add boot catalog if it exists
            if (Test-Path "${extractDir}\isolinux\boot.cat") {
                # Don't recreate boot catalog - use existing one
                Write-Host "  Using existing boot catalog (safer)"
            }
            
            $oscdimgArgs += $extractDir
            $oscdimgArgs += $customISO
            
            Write-Host "  Running: oscdimg $($oscdimgArgs -join ' ')"
            $result = & $isoTool @oscdimgArgs 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                throw "oscdimg failed: $result"
            }
        }
        
        "poweriso" {
            # PowerISO command line
            $powerISOArgs = @(
                "create"
                "-t:iso"
                "-src:${extractDir}"
                "-dest:${customISO}"
                "-bootable"
            )
            
            $result = & $isoTool @powerISOArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "PowerISO failed: $result"
            }
        }
        
        "cdrtfe" {
            # cdrtfe command line (note: cdrtfe is typically GUI-based, but has some CLI support)
            Write-Host "  Note: cdrtfe is primarily a GUI tool. You may need to create the ISO manually."
            Write-Host "  Alternatively, please install PowerISO or use oscdimg as fallback."
            throw "cdrtfe CLI support is limited - please use PowerISO or oscdimg instead"
        }
        
        default {
            throw "Unsupported ISO creation method: $isoMethod"
        }
    }
    
    if (Test-Path $customISO) {
        Write-Host "Success! Custom ISO created: $customISO" -ForegroundColor Green
        $isoSize = (Get-Item $customISO).Length
        Write-Host "ISO size: $([math]::Round($isoSize/1MB,2)) MB"
        
        Write-Host "`n=== Next Steps ===" -ForegroundColor Yellow
        Write-Host "1. Test the ISO with the original AlmaLinux first to ensure it boots"
        Write-Host "2. Update config.yaml: iso_path: `"$customISO`""
        Write-Host "3. Use the provisioning script to create VMs"
        Write-Host "4. If this ISO also has checksum errors, try a different original AlmaLinux ISO"
    } else {
        throw "ISO file was not created"
    }
    
    # Cleanup
    Remove-Item $workDir -Recurse -Force
    
} catch {
    Write-Error "Failed to create custom ISO: $($_.Exception.Message)"
    
    # Cleanup on failure
    if (Test-Path $workDir) {
        Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $customISO) {
        Remove-Item $customISO -Force -ErrorAction SilentlyContinue
    }
    
    Write-Host "`n=== Troubleshooting Tips ===" -ForegroundColor Yellow
    Write-Host "1. Try the original AlmaLinux ISO first to ensure it's not corrupted"
    Write-Host "2. Download a fresh AlmaLinux ISO from official sources"
    Write-Host "3. Try a different AlmaLinux version (8.x vs 9.x)"
    Write-Host "4. Consider using Generation 2 VMs instead of Generation 1"
    Write-Host "5. Verify the original ISO with: certutil -hashfile `"$originalISO`" SHA256"
    
    exit 1
}

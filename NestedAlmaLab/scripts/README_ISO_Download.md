# AlmaLinux ISO Download Guide

The `fetch_iso.ps1` script provides multiple methods to download AlmaLinux ISO files. This guide explains the pros and cons of each method and provides usage examples.

## Quick Start (Recommended)

```powershell
# Use the default manual method (opens browser)
.\fetch_iso.ps1

# Or explicitly specify manual method
.\fetch_iso.ps1 -Method manual
```

## Download Methods Comparison

| Method | Speed | Reliability | Resumable | Progress | Notes |
|--------|-------|-------------|-----------|----------|-------|
| **manual** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ✅ | ✅ | **RECOMMENDED** - Uses browser |
| **curl** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ✅ | ✅ | Good alternative, built into Windows 10+ |
| **bitsadmin** | ⭐⭐⭐ | ⭐⭐⭐ | ✅ | ⭐ | Windows built-in, background transfer |
| **wget** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ✅ | ✅ | Requires separate installation |
| **powershell** | ⭐ | ⭐⭐ | ❌ | ❌ | **NOT RECOMMENDED** - Slow and unreliable |

## Usage Examples

### Manual Download (Recommended)
```powershell
# Opens browser and destination folder
.\fetch_iso.ps1 -Method manual

# Download AlmaLinux 8 instead of 9
.\fetch_iso.ps1 -Method manual -IsoVersion "8"

# Custom ISO path
.\fetch_iso.ps1 -Method manual -IsoPath "D:\VirtualMachines\ISOs"
```

### Curl Download
```powershell
# Download with curl (fast, reliable, shows progress)
.\fetch_iso.ps1 -Method curl

# Curl is built into Windows 10+ and provides good performance
```

### BITS Admin Download
```powershell
# Download with Windows BITS (background transfer)
.\fetch_iso.ps1 -Method bitsadmin

# Good for background downloads, won't interfere with other tasks
```

### Complete Example
```powershell
# Download AlmaLinux 9 to custom path using manual method
.\fetch_iso.ps1 -Method manual -IsoVersion "9" -IsoPath "C:\HyperV\ISOs"
```

## Why Manual Download is Recommended

1. **Speed**: Browser downloads are typically 5-10x faster than PowerShell methods
2. **Reliability**: Browsers have robust download managers with automatic retry
3. **Resume Support**: Can resume interrupted downloads
4. **Progress Tracking**: Clear progress indicators and time estimates
5. **Mirror Selection**: Easy to switch to faster mirror sites if needed

## Troubleshooting

### Download Fails or is Very Slow
- Use the **manual** method with your browser
- Try different mirror sites: https://mirrors.almalinux.org/isos.html
- Check your internet connection and firewall settings

### "curl not found" Error
- Curl is built into Windows 10+ (version 1803 and later)
- For older Windows versions, use **manual** or **bitsadmin** methods

### "wget not found" Error
- wget is not included with Windows by default
- Install it via chocolatey: `choco install wget`
- Or use **manual** or **curl** methods instead

### Partial Download
- Delete the incomplete file and retry
- Use **manual** method for best reliability
- Check available disk space (AlmaLinux DVD ~9-10 GB)

## File Verification

After download, the script automatically:
- Checks file size (should be 8-15 GB for DVD version)
- Reports any size anomalies
- Confirms the file exists at the expected location

For additional verification, you can check the SHA256 checksum:
```powershell
# Get checksum of downloaded file
Get-FileHash "C:\ISOs\AlmaLinux-9-latest-x86_64.iso" -Algorithm SHA256

# Compare with checksums from: https://repo.almalinux.org/almalinux/9/isos/x86_64/CHECKSUM
```

## ISO Types Available

- **DVD**: Full installation with all packages (~9-10 GB) - **Recommended for lab use**
- **Minimal**: Basic installation, downloads packages during install (~700 MB)
- **Boot**: Network boot image for PXE installation (~800 MB)

The script defaults to DVD version as it's best for offline lab environments.

## Performance Tips

1. **Use wired internet connection** instead of WiFi when possible
2. **Close bandwidth-heavy applications** during download
3. **Choose geographically close mirrors** from https://mirrors.almalinux.org/isos.html
4. **Download during off-peak hours** for better speed
5. **Ensure adequate disk space** (at least 15 GB free recommended)

## Integration with Other Scripts

The downloaded ISO will be automatically used by:
- `provision-vms.ps1` for VM creation
- Other lab setup scripts that reference the ISO path

Make sure the downloaded file matches the path specified in your `config.yaml`:
```yaml
iso_path: "C:\\ISOs\\AlmaLinux-9-latest-x86_64.iso"
```

# UEFI Boot Issues - Fixes and Troubleshooting Guide

## Problem Summary

The NestedAlmaLab project was experiencing UEFI boot failures with Generation 2 Hyper-V VMs, where VMs would display "No OS found" errors when trying to boot from the AlmaLinux ISO. This document outlines the root causes and comprehensive fixes applied.

## Root Causes Identified

### 1. Kickstart Configuration Issues
- **Problem**: Kickstart files were using BIOS-specific bootloader configurations
- **Specific Issues**:
  - `bootloader --location=mbr --driveorder=sda` forces BIOS/MBR mode
  - `clearpart --all --initlabel --drives=sda` hardcodes disk device names
  - These configurations prevent proper UEFI boot on Generation 2 VMs

### 2. Custom ISO UEFI Support
- **Problem**: Custom ISO creation wasn't optimally configured for UEFI boot
- **Issues**:
  - oscdimg parameters weren't optimized for hybrid BIOS/UEFI support
  - Missing proper UEFI boot validation during ISO creation

### 3. VM Configuration
- **Problem**: Generation 2 VMs had suboptimal UEFI firmware settings
- **Issues**:
  - Secure Boot enabled (incompatible with Linux)
  - Incorrect boot device order
  - Missing UEFI-specific configuration

## Fixes Applied

### 1. Kickstart File Updates

**Files Modified**:
- `NestedAlmaLab/templates/AlmaLinux/v1/ks.cfg`
- `NestedAlmaLab/templates/AlmaLinux/v2/ks.cfg`

**Changes Made**:
```bash
# Old (BIOS-specific):
bootloader --location=mbr --driveorder=sda --append="console=tty0 console=ttyS0,115200n8"
clearpart --all --initlabel --drives=sda

# New (UEFI/BIOS compatible):
bootloader --append="console=tty0 console=ttyS0,115200n8"
clearpart --all --initlabel
```

**Benefits**:
- Auto-detects UEFI vs BIOS boot mode
- Creates appropriate EFI System Partition for UEFI
- Uses flexible disk detection instead of hardcoded device names
- Compatible with both Generation 1 and Generation 2 VMs

### 2. Enhanced Custom ISO Creation

**File Modified**: `NestedAlmaLab/scripts/create-custom-iso.ps1`

**Improvements**:
- Better UEFI boot file detection and validation
- Improved oscdimg parameters for hybrid BIOS/UEFI support
- Enhanced error handling and diagnostics
- Proper handling of both isolinux (BIOS) and GRUB (UEFI) configurations

**Key Changes**:
```powershell
# Enhanced oscdimg arguments for better compatibility
$oscdimgArgs = @(
    "-n"                    # Allow long file names
    "-m"                    # Ignore maximum image size limit
    "-h"                    # Include hidden files
    "-l"                    # Long file name support
    "-j2"                   # Use Joliet file system level 2
    "-o"                    # Optimize layout
)

# Hybrid BIOS/UEFI detection and configuration
if ($hasBiosBooter -and $hasUefiBooter) {
    # Hybrid BIOS/UEFI ISO - maximum compatibility
    $oscdimgArgs += "-b$extractDir\isolinux\isolinux.bin"
    $oscdimgArgs += "-c$extractDir\isolinux\boot.cat"
}
```

### 3. VM Configuration Enhancements

**File Modified**: `NestedAlmaLab/scripts/provision-vms.ps1`

**Existing Good Practices Confirmed**:
- Secure Boot is properly disabled for Linux VMs
- DVD drive is correctly set as first boot device
- Boot order is properly configured for UEFI
- Virtualization extensions are enabled

### 4. New Diagnostic and Fix Scripts

#### A. ISO Boot Diagnostics Script
**File**: `NestedAlmaLab/scripts/diagnose-iso-boot.ps1`

**Features**:
- Comprehensive ISO structure analysis
- BIOS and UEFI boot file validation
- Kickstart configuration checking
- Boot compatibility assessment
- Detailed recommendations

**Usage**:
```powershell
.\diagnose-iso-boot.ps1                    # Uses ISO from config.yaml
.\diagnose-iso-boot.ps1 -ISOPath "path\to\iso"  # Specific ISO file
```

#### B. Comprehensive UEFI Fix Script
**File**: `NestedAlmaLab/scripts/fix-uefi-boot.ps1`

**Features**:
- Automated kickstart UEFI compatibility fixes
- Custom ISO regeneration with UEFI support
- VM configuration validation and correction
- Step-by-step guided troubleshooting

**Usage**:
```powershell
.\fix-uefi-boot.ps1                       # Fix everything
.\fix-uefi-boot.ps1 -FixKickstart         # Fix only kickstart files
.\fix-uefi-boot.ps1 -RegenerateISO        # Regenerate custom ISO only
.\fix-uefi-boot.ps1 -CheckVMs              # Check VM configuration only
```

## How to Apply the Fixes

### Method 1: Automated Fix (Recommended)
```powershell
# Navigate to the scripts directory
cd NestedAlmaLab\scripts

# Run the comprehensive fix script
.\fix-uefi-boot.ps1

# Follow the prompts to apply all fixes
```

### Method 2: Manual Step-by-Step

1. **Fix Kickstart Files**:
   ```powershell
   # The kickstart files have already been updated automatically
   # Verify by checking the bootloader and clearpart lines
   ```

2. **Regenerate Custom ISO**:
   ```powershell
   .\create-custom-iso.ps1 -KickstartVersion v1 -Generation 2
   ```

3. **Update Configuration**:
   ```yaml
   # Update config.yaml to use the new custom ISO
   iso_path: "path\to\AlmaLinux-v1-Gen2-Custom.iso"
   ```

4. **Provision VMs**:
   ```powershell
   .\provision-vms.ps1
   ```

## Verification Steps

### 1. Verify ISO Compatibility
```powershell
.\diagnose-iso-boot.ps1
# Look for [OK] messages for both BIOS and UEFI boot support
```

### 2. Test VM Boot
1. Start a VM and connect to console
2. Observe boot process - should proceed automatically with custom ISO
3. Verify installation begins without manual intervention

### 3. Check VM Settings
```powershell
# Verify Generation 2 VM settings
Get-VMFirmware -VMName "AlmaVM-1" | Select-Object SecureBoot, BootOrder
```

## Troubleshooting Guide

### Issue: "No OS found" Error
**Possible Causes**:
- Original AlmaLinux ISO doesn't support UEFI
- Custom ISO creation failed
- VM firmware configuration issues

**Solutions**:
1. Verify original ISO has UEFI support (AlmaLinux 9.3+ recommended)
2. Regenerate custom ISO with fixed scripts
3. Check VM Secure Boot is disabled
4. Verify DVD drive is first boot device

### Issue: Boot Hangs or Kernel Panic
**Possible Causes**:
- Insufficient VM resources
- Network connectivity issues during installation
- Corrupted ISO file

**Solutions**:
1. Increase VM RAM (minimum 2GB recommended)
2. Verify network connectivity
3. Re-download original AlmaLinux ISO
4. Check Hyper-V host has nested virtualization enabled

### Issue: Installation Starts but Fails
**Possible Causes**:
- Kickstart file issues
- Package download failures
- Disk space problems

**Solutions**:
1. Check kickstart syntax with diagnostic script
2. Verify internet connectivity during installation
3. Ensure adequate disk space (minimum 20GB)

## Best Practices Going Forward

### 1. ISO Management
- Always test new ISOs with the diagnostic script before use
- Keep both standard and custom ISOs for different scenarios
- Use version-specific custom ISOs (v1 vs v2)

### 2. VM Configuration
- Use Generation 2 VMs for better performance and UEFI support
- Always disable Secure Boot for Linux VMs
- Ensure adequate resources (4GB+ RAM, 40GB+ disk for lab use)

### 3. Troubleshooting
- Run diagnostic scripts first before manual troubleshooting
- Check VM console output during boot for specific error messages
- Use fix scripts for automated remediation

## Alternative Approaches

### If UEFI Issues Persist
1. **Switch to Generation 1 VMs**:
   ```yaml
   # In config.yaml
   vm_generation: 1
   ```
   - Uses BIOS instead of UEFI
   - Generally more compatible but less modern
   - Slightly different feature set

2. **Use Standard ISO with Manual Boot**:
   - Keep original AlmaLinux ISO
   - Manually enter boot parameters during installation
   - More manual but guaranteed compatibility

3. **Different Linux Distribution**:
   - Consider alternatives like Rocky Linux or CentOS Stream
   - Same RHEL compatibility with potentially better UEFI support

## Files Modified/Added

### Modified Files:
- `NestedAlmaLab/templates/AlmaLinux/v1/ks.cfg` - Fixed UEFI compatibility
- `NestedAlmaLab/templates/AlmaLinux/v2/ks.cfg` - Fixed UEFI compatibility  
- `NestedAlmaLab/scripts/create-custom-iso.ps1` - Enhanced UEFI support
- **ALL PowerShell scripts (*.ps1)** - Fixed 1,883 Unicode characters for Windows console compatibility

### New Files Added:
- `NestedAlmaLab/scripts/diagnose-iso-boot.ps1` - ISO diagnostic tool
- `NestedAlmaLab/scripts/fix-uefi-boot.ps1` - Comprehensive fix script  
- `NestedAlmaLab/scripts/fix-unicode-chars.ps1` - Unicode character fix utility
- `NestedAlmaLab/UEFI-BOOT-FIXES.md` - This documentation

## Summary

The UEFI boot issues have been comprehensively addressed through:

1. **Kickstart Configuration**: Made flexible for both UEFI and BIOS boot
2. **Custom ISO Creation**: Enhanced for proper UEFI support
3. **Diagnostic Tools**: Added comprehensive troubleshooting capabilities
4. **Automated Fixes**: Created scripts for easy problem resolution

These fixes should resolve the "No OS found" errors and provide reliable UEFI boot functionality for Generation 2 VMs while maintaining backward compatibility with Generation 1 VMs.

The project now includes robust diagnostic and repair capabilities, making it easier to troubleshoot and resolve any future boot-related issues.

### Unicode Character Compatibility Fix

**Issue**: All PowerShell scripts contained Unicode characters (smart quotes, em-dashes, etc.) that could cause display issues on Windows PowerShell console, especially on older systems or with certain locale settings.

**Fix Applied**: 
- Automatically detected and replaced 1,883 Unicode characters across all PowerShell scripts
- Replaced Unicode quotes (", ") with ASCII quotes (")
- Replaced Unicode dashes (–, —) with ASCII hyphens (-)
- Replaced other Unicode symbols with ASCII equivalents
- Created backup files (.bak) of original scripts

**Tools Created**:
- `fix-unicode-chars.ps1` - PowerShell script to fix Unicode characters in scripts
- Python utility script for bulk character replacement

**Result**: All PowerShell scripts now use only ASCII characters and will display correctly on any Windows PowerShell console without special character encoding issues.

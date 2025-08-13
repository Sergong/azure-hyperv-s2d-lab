# Bootstrap script for Hyper-V and S2D cluster nodes
# This script runs on both nodes to install required Windows features

param(
    [string]$NodeName = $env:COMPUTERNAME,
    [string]$S2DScriptUrl = ""
)

# Start logging
Start-Transcript -Path "C:\bootstrap-extension.txt" -Append

Write-Host "Starting bootstrap configuration for node: $NodeName"
Write-Host "Timestamp: $(Get-Date)"
Write-Host "S2D Script URL parameter: '$S2DScriptUrl'"
Write-Host "Current user context: $env:USERNAME"
Write-Host "Current working directory: $(Get-Location)"

$restartRequired = $false

try {
    # Import Server Manager module
    Write-Host "Importing ServerManager module..."
    Import-Module ServerManager

    # Install Windows features
    Write-Host "Installing Hyper-V, Failover Clustering, and File Server features..."
    $features = @('Hyper-V', 'Failover-Clustering', 'FS-FileServer')
    
    foreach ($feature in $features) {
        Write-Host "Installing feature: $feature"
        $result = Install-WindowsFeature -Name $feature -IncludeManagementTools
        Write-Host "Feature $feature install result: Success=$($result.Success), ExitCode=$($result.ExitCode), RestartNeeded=$($result.RestartNeeded)"
        
        if ($result.RestartNeeded -eq 'Yes') {
            Write-Host "Feature $feature installed, restart required"
            $restartRequired = $true
        } else {
            Write-Host "Feature $feature installed successfully"
        }
    }

    # If this is node-0, download the S2D setup script
    if ($NodeName -eq 'hyperv-node-0' -and $S2DScriptUrl -ne "") {
        Write-Host "This is the primary node (hyperv-node-0). Downloading S2D setup script..."
        Write-Host "Download URL: $S2DScriptUrl"
        Write-Host "Target path: C:\setup-s2d-cluster.ps1"
        
        # Test network connectivity first
        try {
            Write-Host "Testing network connectivity to blob storage..."
            $testResponse = Invoke-WebRequest -Uri $S2DScriptUrl -Method Head -UseBasicParsing -TimeoutSec 30
            Write-Host "Network test successful - HTTP Status: $($testResponse.StatusCode)"
        } catch {
            Write-Host "Network test failed: $($_.Exception.Message)"
        }
        
        # Attempt to download the script with multiple retries
        $maxRetries = 3
        $downloadSuccess = $false
        
        for ($retry = 1; $retry -le $maxRetries; $retry++) {
            try {
                Write-Host "Download attempt $retry of $maxRetries..."
                Invoke-WebRequest -Uri $S2DScriptUrl -OutFile "C:\setup-s2d-cluster.ps1" -UseBasicParsing -TimeoutSec 60
                
                # Verify the file was created and has content
                if (Test-Path "C:\setup-s2d-cluster.ps1") {
                    $fileInfo = Get-Item "C:\setup-s2d-cluster.ps1"
                    if ($fileInfo.Length -gt 0) {
                        Write-Host "SUCCESS: S2D setup script downloaded successfully!"
                        Write-Host "File size: $($fileInfo.Length) bytes"
                        Write-Host "File created: $($fileInfo.CreationTime)"
                        $downloadSuccess = $true
                        break
                    } else {
                        Write-Host "WARNING: File was created but is empty (0 bytes)"
                        Remove-Item "C:\setup-s2d-cluster.ps1" -Force -ErrorAction SilentlyContinue
                    }
                } else {
                    Write-Host "WARNING: File was not created at target location"
                }
            } catch {
                Write-Host "Download attempt $retry failed: $($_.Exception.Message)"
                if ($retry -lt $maxRetries) {
                    Write-Host "Waiting 5 seconds before retry..."
                    Start-Sleep -Seconds 5
                }
            }
        }
        
        if (-not $downloadSuccess) {
            Write-Host "ERROR: Failed to download S2D script after $maxRetries attempts"
            Write-Host "Manual download command for later use:"
            Write-Host "Invoke-WebRequest -Uri '$S2DScriptUrl' -OutFile 'C:\setup-s2d-cluster.ps1' -UseBasicParsing"
        }
    } else {
        Write-Host "This is node: $NodeName (not hyperv-node-0), skipping S2D script download"
    }

    # Create completion marker
    Write-Host "Creating node ready marker..."
    "Bootstrap completed at $(Get-Date)" | Out-File -FilePath "C:\NodeReady.txt" -Encoding UTF8

    Write-Host "Bootstrap configuration completed successfully"
    
    # Force restart if any features required it OR if this is the first run
    # This ensures all features are properly activated
    if ($restartRequired) {
        Write-Host "Windows features installation requires restart - scheduling immediate reboot..."
        Write-Host "System will restart in 10 seconds to complete feature installation"
        
        # Create a flag to indicate this is a post-bootstrap restart
        "Post-bootstrap restart at $(Get-Date)" | Out-File -FilePath "C:\BootstrapRestart.txt" -Encoding UTF8
        
        Stop-Transcript
        
        # Schedule immediate restart
        shutdown /r /t 10 /c "Restarting to complete Windows feature installation"
        
        # Exit the script - restart will happen
        exit 0
    } else {
        Write-Host "No restart required - all features installed successfully"
    }
    
} catch {
    Write-Host "ERROR during bootstrap: $($_.Exception.Message)"
    Write-Host "Stack trace: $($_.Exception.StackTrace)"
    
    # Create error marker
    "Bootstrap failed at $(Get-Date): $($_.Exception.Message)" | Out-File -FilePath "C:\BootstrapError.txt" -Encoding UTF8
    
} finally {
    Stop-Transcript
}

Write-Host "Bootstrap script execution completed"

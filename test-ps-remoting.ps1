# PowerShell Remoting Test Script
# This script tests WinRM connectivity between hyperv-node-0 and hyperv-node-1
# Run this on either node to test connectivity to the other node

param(
    [string[]]$TargetNodes = @("hyperv-node-0", "hyperv-node-1"),
    [switch]$SkipCredentialTest = $false
)

Write-Host "==========================================="
Write-Host "PowerShell Remoting Test"
Write-Host "==========================================="
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "Date: $(Get-Date)"
Write-Host "Target Nodes: $($TargetNodes -join ', ')"
Write-Host "==========================================="

# Function to test WinRM connectivity
function Test-WinRMConnectivity {
    param([string]$ComputerName)
    
    Write-Host ""
    Write-Host "Testing WinRM connectivity to $ComputerName..."
    
    try {
        $result = Test-WSMan -ComputerName $ComputerName -ErrorAction Stop
        if ($result) {
            Write-Host "✓ WinRM connectivity to $ComputerName: SUCCESS"
            Write-Host "  ProductVendor: $($result.ProductVendor)"
            Write-Host "  ProductVersion: $($result.ProductVersion)"
            return $true
        }
    } catch {
        Write-Host "✗ WinRM connectivity to $ComputerName: FAILED"
        Write-Host "  Error: $($_.Exception.Message)"
        return $false
    }
}

# Function to test PowerShell remoting with credentials
function Test-PSRemoting {
    param([string]$ComputerName)
    
    Write-Host ""
    Write-Host "Testing PowerShell Remoting to $ComputerName..."
    
    if ($SkipCredentialTest) {
        Write-Host "Skipping credential-based remoting test"
        return $true
    }
    
    try {
        # Try to connect and get computer info
        Write-Host "Attempting to get computer information from $ComputerName..."
        Write-Host "Note: You may be prompted for credentials. Use: .\Administrator or $ComputerName\Administrator"
        
        $result = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            @{
                ComputerName = $env:COMPUTERNAME
                UserName = $env:USERNAME
                Domain = $env:USERDOMAIN
                OSVersion = (Get-CimInstance Win32_OperatingSystem).Caption
                TotalMemory = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
                Timestamp = Get-Date
            }
        } -ErrorAction Stop
        
        if ($result) {
            Write-Host "✓ PowerShell Remoting to $ComputerName: SUCCESS"
            Write-Host "  Remote Computer: $($result.ComputerName)"
            Write-Host "  Remote User: $($result.Domain)\$($result.UserName)"
            Write-Host "  Remote OS: $($result.OSVersion)"
            Write-Host "  Remote Memory: $($result.TotalMemory) GB"
            Write-Host "  Remote Time: $($result.Timestamp)"
            return $true
        }
    } catch {
        Write-Host "✗ PowerShell Remoting to $ComputerName: FAILED"
        Write-Host "  Error: $($_.Exception.Message)"
        
        # Provide troubleshooting guidance
        if ($_.Exception.Message -like "*access is denied*") {
            Write-Host "  Troubleshooting: Try using .\Administrator or $ComputerName\Administrator credentials"
        } elseif ($_.Exception.Message -like "*cannot be resolved*") {
            Write-Host "  Troubleshooting: Check name resolution - try using IP address instead"
        } elseif ($_.Exception.Message -like "*timeout*") {
            Write-Host "  Troubleshooting: Check firewall settings and WinRM service status"
        }
        
        return $false
    }
}

# Function to test cluster prerequisites
function Test-ClusterPrerequisites {
    param([string[]]$ComputerNames)
    
    Write-Host ""
    Write-Host "Testing cluster prerequisites..."
    
    try {
        Write-Host "Testing cluster validation prerequisites..."
        
        # Test if we can run cluster commands remotely
        foreach ($computer in $ComputerNames) {
            if ($computer -ne $env:COMPUTERNAME) {
                Write-Host "Testing failover clustering features on $computer..."
                
                $clusterFeature = Invoke-Command -ComputerName $computer -ScriptBlock {
                    Get-WindowsFeature -Name "Failover-Clustering" -ErrorAction SilentlyContinue
                } -ErrorAction SilentlyContinue
                
                if ($clusterFeature -and $clusterFeature.InstallState -eq "Installed") {
                    Write-Host "✓ Failover Clustering feature installed on $computer"
                } else {
                    Write-Host "✗ Failover Clustering feature not installed on $computer"
                }
            }
        }
        
        return $true
    } catch {
        Write-Host "✗ Cluster prerequisites test failed: $($_.Exception.Message)"
        return $false
    }
}

# Main test execution
Write-Host ""
Write-Host "Starting PowerShell Remoting tests..."

$allTestsPassed = $true
$connectedNodes = @()

# Test WinRM connectivity to each target node
foreach ($node in $TargetNodes) {
    if ($node -ne $env:COMPUTERNAME) {
        $connectivityResult = Test-WinRMConnectivity -ComputerName $node
        if ($connectivityResult) {
            $connectedNodes += $node
        } else {
            $allTestsPassed = $false
        }
    } else {
        Write-Host ""
        Write-Host "Skipping $node (current computer)"
    }
}

# Test PowerShell Remoting if WinRM connectivity passed
if ($connectedNodes.Count -gt 0 -and -not $SkipCredentialTest) {
    foreach ($node in $connectedNodes) {
        $remotingResult = Test-PSRemoting -ComputerName $node
        if (-not $remotingResult) {
            $allTestsPassed = $false
        }
    }
}

# Test cluster prerequisites if basic connectivity works
if ($connectedNodes.Count -gt 0) {
    $clusterResult = Test-ClusterPrerequisites -ComputerNames $TargetNodes
    if (-not $clusterResult) {
        $allTestsPassed = $false
    }
}

# Display final results
Write-Host ""
Write-Host "==========================================="
Write-Host "TEST RESULTS SUMMARY"
Write-Host "==========================================="

if ($allTestsPassed) {
    Write-Host "✓ ALL TESTS PASSED"
    Write-Host "PowerShell Remoting is working correctly between nodes"
    Write-Host "Cluster configuration should be able to proceed"
} else {
    Write-Host "✗ SOME TESTS FAILED"
    Write-Host "PowerShell Remoting needs attention before proceeding with clustering"
}

Write-Host ""
Write-Host "Connected Nodes: $($connectedNodes -join ', ')"
Write-Host "Failed Nodes: $(($TargetNodes | Where-Object { $_ -notin $connectedNodes -and $_ -ne $env:COMPUTERNAME }) -join ', ')"

Write-Host ""
Write-Host "==========================================="
Write-Host "TROUBLESHOOTING COMMANDS"
Write-Host "==========================================="
Write-Host "Check WinRM configuration:"
Write-Host "  winrm get winrm/config"
Write-Host "  Get-Item WSMan:\localhost\Client\TrustedHosts"
Write-Host ""
Write-Host "Manual connectivity tests:"
Write-Host "  Test-WSMan hyperv-node-0"
Write-Host "  Test-WSMan hyperv-node-1"
Write-Host ""
Write-Host "Test with credentials:"
Write-Host "  Enter-PSSession -ComputerName hyperv-node-0 -Credential (Get-Credential)"
Write-Host "  (Use .\Administrator or COMPUTERNAME\Administrator)"
Write-Host ""
Write-Host "Check firewall rules:"
Write-Host "  Get-NetFirewallRule -DisplayName '*WinRM*' | Select DisplayName, Enabled, Action"

Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

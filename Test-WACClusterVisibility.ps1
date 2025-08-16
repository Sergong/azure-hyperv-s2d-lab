param (
    [string]$ClusterName = "s2Dcluster",
    [string[]]$NodeList = @("hyperv-node-0", "hyperv-node-1"),
    [string]$ExpectedIP = "10.0.1.7"
)

function Test-ClusterService {
    param([string]$Node)
    $svc = Invoke-Command -ComputerName $Node -ScriptBlock {
        Get-Service -Name clusSvc
    } -ErrorAction SilentlyContinue
    if ($svc.Status -eq 'Running') {
        return @{ Node = $Node; ClusterService = 'Running' }
    } else {
        return @{ Node = $Node; ClusterService = 'Not Running' }
    }
}

function Test-ClusterMembership {
    param([string]$Node)
    $nodes = Invoke-Command -ComputerName $Node -ScriptBlock {
        try {
            Get-ClusterNode | Select-Object -ExpandProperty Name
        } catch {
            return $null
        }
    } -ErrorAction SilentlyContinue
    return @{ Node = $Node; ClusterNodes = $nodes }
}

function Test-ClusterIPResource {
    param([string]$Node)
    $ipResource = Invoke-Command -ComputerName $Node -ScriptBlock {
        try {
            Get-ClusterResource | Where-Object { $_.ResourceType -eq "IP Address" }
        } catch {
            return $null
        }
    } -ErrorAction SilentlyContinue
    return @{ Node = $Node; IPResourceFound = ($ipResource -ne $null -and $ipResource.Count -gt 0) }
}

function Test-WinRMListener {
    param([string]$Node)
    $listeners = Invoke-Command -ComputerName $Node -ScriptBlock {
        winrm enumerate winrm/config/listener
    } -ErrorAction SilentlyContinue
    return @{ Node = $Node; ListenerOutput = $listeners }
}

function Test-ClusterNameResolution {
    param([string]$ClusterName)
    try {
        $resolved = [System.Net.Dns]::GetHostAddresses($ClusterName)
        return @{ ClusterName = $ClusterName; Resolved = $true; IPs = $resolved.IPAddressToString }
    } catch {
        return @{ ClusterName = $ClusterName; Resolved = $false }
    }
}

Write-Host "`n=== WAC Cluster Visibility Diagnostics ===`n"

# Cluster Name Resolution
$res = Test-ClusterNameResolution -ClusterName $ClusterName
$res | Format-List

# Node Diagnostics
foreach ($node in $NodeList) {
    Write-Host "`n--- $node ---"
    Test-ClusterService -Node $node | Format-List
    Test-ClusterMembership -Node $node | Format-List
    Test-ClusterIPResource -Node $node | Format-List
    Test-WinRMListener -Node $node | Format-List
}

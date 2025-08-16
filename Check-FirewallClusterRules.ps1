# Check if FOCM FW rules are present
param (
    [switch]$Remediate
)

function Resolve-FQDN {
    param ($Name)
    try {
        $fqdn = [System.Net.Dns]::GetHostEntry($Name).HostName
        Write-Host "Resolved $Name → $fqdn"
        return $fqdn
    } catch {
        Write-Warning "DNS resolution failed for $Name. Using original name."
        return $Name
    }
}

$nodes = @("hyperv-node-0", "hyperv-node-1")

$fqdnList = @()
foreach ($name in $nodes) {
    $fqdnList += Resolve-FQDN -Name $name
}

Write-Host "`nFinal FQDN list:"
$fqdnList | ForEach-Object { Write-Host $_ }

if($Remediate){
  .\Test-FirewallClusterRules.ps1 -ClusterNodes $fqdnList -Remediate
} else {
  .\Test-FirewallClusterRules.ps1 -ClusterNodes $fqdnList
}

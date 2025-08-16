# Check if FOCM FW rules are present
param (
    [switch]$Remediate
)

. .\Resolve-FQDN-Function.ps1

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

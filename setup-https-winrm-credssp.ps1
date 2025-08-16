# setup winrm and credssp

. .\Resolve-FQDN-Function.ps1

$nodes = @("hyperv-node-0", "hyperv-node-1")

$fqdnList = @()
foreach ($name in $nodes) {
    $fqdnList += Resolve-FQDN -Name $name
}

Write-Host "`nFinal FQDN list:"
$fqdnList | ForEach-Object { Write-Host $_ }

write-host "You will be prompted for credentials several times!" -ForegroundColor Cyan
.\configure-credssp-winrm.ps1 -ClusterNodes $fqdnList


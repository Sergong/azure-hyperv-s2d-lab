# setup winrm and credssp
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

write-host "You will be prompted for credentials several times!" -ForegroundColor Cyan
.\configure-credssp-winrm.ps1 -ClusterNodes $fqdnList


<#
    Function module to source in scripts that require the functions.
#>

function Resolve-FQDN {
    param ($Name)
    try {
        $fqdn = [System.Net.Dns]::GetHostEntry($Name).HostName
        Write-Host "Resolved $Name → $fqdn"
        return $fqdn
    } catch {
        Write-Warning "DNS resolution failed for $Name. Trying DNS Connection Suffix for 10.* Interface."
        $nic = (Get-NetIPAddress | Where-Object{$_.AddressFamily -eq "IPv4" -and $_.IPAddress -like "10.*"} | select-object InterfaceAlias).InterfaceAlias
        $NewName = (Get-DnsClient | Where-Object InterfaceAlias -eq $nic | select ConnectionSpecificSuffix).ConnectionSpecificSuffix
        return $NewName
    }
}

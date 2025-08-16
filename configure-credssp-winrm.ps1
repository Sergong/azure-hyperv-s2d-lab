param (
    [string[]]$ClusterNodes,
    [string]$CertCN = "WinRM HTTPS",
    [int]$CertYears = 5
)

function Enable-CredSSP {
    Write-Host "🔐 Enabling CredSSP on gateway..." -ForegroundColor Cyan
    Enable-WSManCredSSP -Role Client -DelegateComputer $ClusterNodes -Force

    foreach ($node in $ClusterNodes) {
        Write-Host "🔐 Enabling CredSSP on $node..." -ForegroundColor Cyan
        Invoke-Command -ComputerName $node -ScriptBlock {
            Enable-WSManCredSSP -Role Server -Force
        } -Authentication Credssp -Credential (Get-Credential)
    }
}

function Resolve-FQDNs {
    Write-Host "🌐 Resolving FQDNs..." -ForegroundColor Cyan
    $fqdnMap = @{}
    foreach ($node in $ClusterNodes) {
        try {
            $fqdn = [System.Net.Dns]::GetHostEntry($node).HostName
            $fqdnMap[$node] = $fqdn
        } catch {
            Write-Warning "DNS resolution failed for $node"
            $fqdnMap[$node] = $node
        }
    }
    return $fqdnMap
}

function Enable-WinRMHTTPS {
    param ($Node)

    Write-Host "🔒 Configuring WinRM HTTPS on $Node..." -ForegroundColor Cyan
    Invoke-Command -ComputerName $Node -ScriptBlock {
        param($CertCN, $CertYears)

        $cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My -FriendlyName $CertCN -NotAfter (Get-Date).AddYears($CertYears)
        $thumb = $cert.Thumbprint

        winrm create winrm/config/Listener?Address=*+Transport=HTTPS "@{Hostname=`"$env:COMPUTERNAME`";CertificateThumbprint=`"$thumb`"}"
        Enable-PSRemoting -Force
    } -ArgumentList $CertCN, $CertYears -Authentication Credssp -Credential (Get-Credential)
}

function Configure-FirewallRules {
    param ($Node)

    Write-Host "🔥 Validating firewall rules on $Node..." -ForegroundColor Cyan
    Invoke-Command -ComputerName $Node -ScriptBlock {
        $groups = @(
            "Windows Remote Management",
            "Remote Shutdown",
            "Remote Volume Management",
            "Remote Event Log Management",
            "Failover Cluster Management"
        )
        foreach ($group in $groups) {
            $rules = Get-NetFirewallRule -DisplayGroup $group -ErrorAction SilentlyContinue
            if ($rules) {
                $rules | Set-NetFirewallRule -Enabled True
                Write-Host "✅ Enabled: $group"
            } else {
                Write-Warning "⚠️ Rule group not found: $group"
            }
        }
    } -Authentication Credssp -Credential (Get-Credential)
}

function Configure-TrustedHosts {
    param ($FQDNs)

    $trustedList = ($FQDNs -join ",")
    Write-Host "🧭 Setting TrustedHosts to: $trustedList" -ForegroundColor Cyan
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value $trustedList
    Restart-Service WinRM

    # Validation
    $current = (Get-Item WSMan:\localhost\Client\TrustedHosts).Value
    if ($current -eq $trustedList) {
        Write-Host "✅ TrustedHosts successfully set." -ForegroundColor Green
    } else {
        Write-Warning "❌ TrustedHosts mismatch. Current value: $current"
    }
}

# Main Execution
$fqdnMap = Resolve-FQDNs
Configure-TrustedHosts -FQDNs $fqdnMap.Values
Enable-CredSSP

foreach ($node in $fqdnMap.Values) {
    Enable-WinRMHTTPS -Node $node
    Configure-FirewallRules -Node $node
}

Write-Host "`n✅ Configuration complete. FQDN map:" -ForegroundColor Green
$fqdnMap | Format-Table -AutoSize

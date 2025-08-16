param (
    [string[]]$ClusterNodes,
    [switch]$Remediate
)

function Test-And-FixFirewallRules {
    param ($Node)

    Write-Host "Checking firewall rules on $Node..."
    Invoke-Command -ComputerName $Node -ScriptBlock {
        $expectedRules = @(
            "Cluster Service (TCP-In)",
            "Cluster Service (UDP-In)",
            "Remote Cluster Management (RPC)",
            "Remote Cluster Management (RPC-EPMAP)",
            "Windows Remote Management (HTTP-In)",
            "Windows Remote Management (HTTPS-In)",
            "Remote Shutdown",
            "Remote Volume Management",
            "Remote Event Log Management"
        )

        $results = @()
        foreach ($ruleName in $expectedRules) {
            $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
            $null = $rule  # Suppress default object output

            if ($rule) {
                $status = if ($rule.Enabled -eq "True") { "Enabled" } else { "Disabled" }
                if ($status -eq "Disabled" -and $using:Remediate) {
                    Enable-NetFirewallRule -DisplayName $ruleName
                    $status = "Remediated"
                }
            } else {
                $status = "Missing"
                if ($using:Remediate) {
                    # Create a basic inbound rule as a fallback
                    New-NetFirewallRule -DisplayName $ruleName `
                        -Direction Inbound -Action Allow `
                        -Protocol TCP -LocalPort 3343 `
                        -Profile Any -Enabled True `
                        -Group "Failover Clustering"
                    $status = "Created"
                }
            }

            $results += [PSCustomObject]@{
                Node     = $env:COMPUTERNAME
                RuleName = $ruleName
                Status   = $status
            }
        }
        return $results

    } -Credential (Get-Credential) -Authentication Credssp
}

# Main Execution
$summary = @()
foreach ($node in $ClusterNodes) {
    $summary += Test-And-FixFirewallRules -Node $node
}

Write-Host "`nFirewall Rule Summary:"
$summary | Format-Table Node, RuleName, Status -AutoSize

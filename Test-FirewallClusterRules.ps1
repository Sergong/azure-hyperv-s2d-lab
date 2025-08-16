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
            if ($rule) {
                $status = if ($rule.Enabled -eq "True") { "Enabled" } else { "Disabled" }
                if ($status -eq "Disabled") {
                    if ($using:Remediate) {
                        $rule | Set-NetFirewallRule -Enabled True
                        $status = "Remediated"
                    }
                }
            } else {
                $status = "Missing"
            }
            $results += [PSCustomObject]@{
                Node       = $env:COMPUTERNAME
                RuleName   = $ruleName
                Status     = $status
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

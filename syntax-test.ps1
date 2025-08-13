# Simple syntax test
param([string]$Test = "value")

try {
    if ($Test -eq "value") {
        Write-Host "Test passed"
    } else {
        Write-Host "Test failed"
    }
} catch {
    Write-Error "Error occurred"
}

Write-Host "Script completed"

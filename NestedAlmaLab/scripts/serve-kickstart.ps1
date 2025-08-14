# Simple HTTP server for serving kickstart files
# This eliminates the need for custom ISOs or floppy disks

param(
    [Parameter(Mandatory=$false)]
    [int]$Port = 8080,
    
    [Parameter(Mandatory=$false)]
    [string]$KickstartVersion = "v1"
)

# Load configuration
$configPath = Join-Path $PSScriptRoot "config.yaml"
if (-not (Test-Path $configPath)) {
    Write-Error "Configuration file not found: $configPath"
    exit 1
}

function ConvertFrom-Yaml {
    param([string]$YamlContent)
    $config = @{}
    $lines = $YamlContent -split "`n" | Where-Object { $_ -match '^\s*\w+:' }
    foreach ($line in $lines) {
        if ($line -match '^\s*([^:]+):\s*"?([^"]+)"?\s*$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim().Trim('"')
            $config[$key] = $value
        }
    }
    return $config
}

$yamlContent = Get-Content $configPath -Raw
$config = ConvertFrom-Yaml -YamlContent $yamlContent

$kickstartFile = Join-Path $PSScriptRoot "..\\templates\\AlmaLinux\\$KickstartVersion\\ks.cfg"
$kickstartDir = Split-Path $kickstartFile -Parent

if (-not (Test-Path $kickstartFile)) {
    Write-Error "Kickstart file not found: $kickstartFile"
    exit 1
}

Write-Host "=== Kickstart HTTP Server ===" -ForegroundColor Cyan
Write-Host "Serving kickstart files from: $kickstartDir"
Write-Host "Port: $Port"
Write-Host "Kickstart URL: http://localhost:${Port}/ks.cfg"
Write-Host ""
Write-Host "Use this boot parameter for AlmaLinux installation:"
Write-Host "inst.ks=http://HOST_IP:${Port}/ks.cfg inst.text console=tty0 console=ttyS0,115200" -ForegroundColor Yellow
Write-Host ""
Write-Host "Press Ctrl+C to stop the server"
Write-Host "================================"

try {
    # Create simple HTTP server using .NET HttpListener
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://+:${Port}/")
    $listener.Start()
    
    Write-Host "HTTP server started successfully on port $Port" -ForegroundColor Green
    
    # Get local IP address for instructions
    $localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
    if ($localIP) {
        Write-Host "Use this URL in boot parameters: http://${localIP}:${Port}/ks.cfg" -ForegroundColor Green
    }
    
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Request from $($request.RemoteEndPoint): $($request.Url.LocalPath)"
        
        if ($request.Url.LocalPath -eq "/ks.cfg") {
            # Serve the kickstart file
            $content = Get-Content $kickstartFile -Raw
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($content)
            
            $response.ContentType = "text/plain"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        } else {
            # Serve directory listing
            $html = @"
<html><head><title>Kickstart Server</title></head><body>
<h1>AlmaLinux Kickstart Server</h1>
<ul>
<li><a href="/ks.cfg">ks.cfg (${KickstartVersion})</a></li>
</ul>
<p>Use: inst.ks=http://HOST_IP:${Port}/ks.cfg</p>
</body></html>
"@
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
            $response.ContentType = "text/html"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        
        $response.Close()
    }
} catch {
    Write-Error "HTTP server error: $($_.Exception.Message)"
} finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
    Write-Host "HTTP server stopped."
}

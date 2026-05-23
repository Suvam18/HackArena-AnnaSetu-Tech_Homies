param(
  [int]$Port = 8081,
  [string]$Root = (Get-Location).Path
)

$rootFull = [System.IO.Path]::GetFullPath($Root)
$listener = $null

# Find an available port starting from the requested port
$currentPort = $Port
$started = $false

while (-not $started -and $currentPort -lt ($Port + 100)) {
  try {
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://localhost:$currentPort/")
    $listener.Prefixes.Add("http://127.0.0.1:$currentPort/")
    $listener.Start()
    $started = $true
  } catch {
    if ($listener -ne $null) {
      $listener.Close()
      $listener = $null
    }
    Write-Host "Port $currentPort is in use or unavailable. Trying next port..."
    $currentPort++
  }
}

if (-not $started) {
  Write-Error "Could not start HTTP listener on any port in range $Port - $($Port + 100)."
  exit 1
}

Write-Host "Server started successfully!"
Write-Host "Local URL: http://localhost:$currentPort/"
Write-Host "Local URL: http://127.0.0.1:$currentPort/"
Write-Host "Root Directory: $rootFull"
Write-Host "Press Ctrl+C to stop the server"

function Get-ContentType([string]$path) {
  switch ([System.IO.Path]::GetExtension($path).ToLowerInvariant()) {
    ".html" { "text/html; charset=utf-8" }
    ".htm"  { "text/html; charset=utf-8" }
    ".css"  { "text/css; charset=utf-8" }
    ".js"   { "application/javascript; charset=utf-8" }
    ".json" { "application/json; charset=utf-8" }
    ".png"  { "image/png" }
    ".jpg"  { "image/jpeg" }
    ".jpeg" { "image/jpeg" }
    ".gif"  { "image/gif" }
    ".svg"  { "image/svg+xml" }
    ".ico"  { "image/x-icon" }
    ".txt"  { "text/plain; charset=utf-8" }
    default { "application/octet-stream" }
  }
}

try {
  while ($true) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    try {
      $rawPath = $request.Url.AbsolutePath
      $decoded = [System.Uri]::UnescapeDataString($rawPath)
      if ([string]::IsNullOrWhiteSpace($decoded) -or $decoded -eq "/") {
        $decoded = "/index.html"
      }

      $relative = $decoded.TrimStart("/") -replace "/", "\"
      $candidate = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootFull, $relative))

      if (-not $candidate.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        $response.StatusCode = 403
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("Forbidden")
        $response.ContentType = "text/plain; charset=utf-8"
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
        continue
      }

      if (Test-Path -LiteralPath $candidate -PathType Container) {
        $index = [System.IO.Path]::Combine($candidate, "index.html")
        if (Test-Path -LiteralPath $index -PathType Leaf) {
          $candidate = $index
        }
      }

      if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        $response.StatusCode = 404
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("Not Found")
        $response.ContentType = "text/plain; charset=utf-8"
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
        continue
      }

      $response.StatusCode = 200
      $response.ContentType = Get-ContentType $candidate
      $fileBytes = [System.IO.File]::ReadAllBytes($candidate)
      $response.ContentLength64 = $fileBytes.Length
      $response.OutputStream.Write($fileBytes, 0, $fileBytes.Length)
    } catch {
      if ($null -ne $response) {
        $response.StatusCode = 500
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("Internal Server Error")
        $response.ContentType = "text/plain; charset=utf-8"
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
      }
    } finally {
      if ($null -ne $response) {
        $response.OutputStream.Close()
      }
    }
  }
} finally {
  if ($null -ne $listener) {
    $listener.Stop()
    $listener.Close()
  }
}

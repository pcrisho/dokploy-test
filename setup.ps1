# ==============================================================================
# Dokploy Local Test Environment - Setup Script (PowerShell)
# ==============================================================================
# Usage: .\setup.ps1
# ==============================================================================

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Blue
Write-Host " Dokploy Local Test Environment Setup" -ForegroundColor Blue
Write-Host "========================================" -ForegroundColor Blue
Write-Host ""

# --------------------------------------------------
# 0. Load .env file if it exists
# --------------------------------------------------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile = Join-Path $scriptDir ".env"

if (Test-Path $envFile) {
    Get-Content $envFile | Where-Object { $_ -notmatch "^\s*#" -and $_ -match "=" } | ForEach-Object {
        $key, $value = $_ -split "=", 2
        [System.Environment]::SetEnvironmentVariable($key.Trim(), $value.Trim(), "Process")
    }
    Write-Host "[OK] Loaded configuration from .env" -ForegroundColor Green
} else {
    Write-Host "[INFO] No .env file found, using defaults. Copy .env.example to .env to customize." -ForegroundColor Yellow
}

# Resolve effective values (env file > env var > default)
$portDashboard = if ($env:PORT_DASHBOARD) { [int]$env:PORT_DASHBOARD } else { 3000 }
$portHttp      = if ($env:PORT_HTTP)      { [int]$env:PORT_HTTP }      else { 80 }
$portHttps     = if ($env:PORT_HTTPS)     { [int]$env:PORT_HTTPS }     else { 443 }
$advertiseAddr = if ($env:ADVERTISE_ADDR) { $env:ADVERTISE_ADDR }      else { "127.0.0.1" }
$dokployVersion = if ($env:DOKPLOY_VERSION) { $env:DOKPLOY_VERSION }   else { "latest" }

# --------------------------------------------------
# 1. Check Docker is installed and running
# --------------------------------------------------
try {
    $null = Get-Command docker -ErrorAction Stop
} catch {
    Write-Host "[ERROR] Docker is not installed." -ForegroundColor Red
    Write-Host "Install Docker Desktop from https://www.docker.com/products/docker-desktop/"
    exit 1
}

try {
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Docker not running" }
} catch {
    Write-Host "[ERROR] Docker daemon is not running. Start Docker Desktop first." -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Docker is installed and running." -ForegroundColor Green

# --------------------------------------------------
# 2. Check port availability
# --------------------------------------------------
$portsInUse = @()
foreach ($port in @($portHttp, $portHttps, $portDashboard)) {
    $conn = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    if ($conn) {
        Write-Host "[WARN] Port $port is already in use." -ForegroundColor Yellow
        $portsInUse += $port
    }
}

if ($portsInUse.Count -eq 0) {
    Write-Host "[OK] Required ports ($portHttp, $portHttps, $portDashboard) are available." -ForegroundColor Green
} else {
    Write-Host "[WARN] Some ports are in use. Dokploy may not start correctly." -ForegroundColor Yellow
    $reply = Read-Host "Continue anyway? (y/N)"
    if ($reply -notmatch "^[Yy]$") {
        exit 1
    }
}

# --------------------------------------------------
# 3. Initialize Docker Swarm (if not already)
# --------------------------------------------------
$swarmActive = docker info 2>&1 | Select-String "Swarm: active"
if ($swarmActive) {
    Write-Host "[OK] Docker Swarm is already active." -ForegroundColor Green
} else {
    Write-Host "[...] Initializing Docker Swarm..." -ForegroundColor Blue

    $advertiseAddr2 = if ($env:ADVERTISE_ADDR) { $env:ADVERTISE_ADDR } else { "127.0.0.1" }

    docker swarm init --advertise-addr $advertiseAddr2 2>$null
    if ($LASTEXITCODE -ne 0) {
        # Retry without specifying address
        docker swarm init 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] Could not initialize Docker Swarm." -ForegroundColor Red
            Write-Host "Try setting ADVERTISE_ADDR manually:"
            Write-Host '  $env:ADVERTISE_ADDR = "<your-ip>"'
            Write-Host "  .\setup.ps1"
            exit 1
        }
    }
    Write-Host "[OK] Docker Swarm initialized." -ForegroundColor Green
}

# --------------------------------------------------
# 4. Create overlay network
# --------------------------------------------------
$networkExists = docker network ls --format '{{.Name}}' | Select-String "^dokploy-network$"
if ($networkExists) {
    Write-Host "[OK] Network 'dokploy-network' already exists." -ForegroundColor Green
} else {
    docker network create --driver overlay --attachable dokploy-network
    Write-Host "[OK] Overlay network 'dokploy-network' created." -ForegroundColor Green
}

# --------------------------------------------------
# 5. Create Docker secret for Postgres password
# --------------------------------------------------
$secretExists = docker secret ls --format '{{.Name}}' | Select-String "^dokploy_postgres_password$"
if ($secretExists) {
    Write-Host "[OK] Secret 'dokploy_postgres_password' already exists." -ForegroundColor Green
} else {
    # Generate random password
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $password = [Convert]::ToBase64String($bytes).Substring(0, 32) -replace '[=+/]', 'x'

    $password | docker secret create dokploy_postgres_password -
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Could not create Docker secret." -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] Docker secret created for Postgres password." -ForegroundColor Green
}

# --------------------------------------------------
# 6. Deploy the stack
# --------------------------------------------------
Write-Host "[...] Deploying Dokploy stack..." -ForegroundColor Blue

$composeFile = Join-Path $scriptDir "docker-compose.yml"

$env:PORT_DASHBOARD  = "$portDashboard"
$env:PORT_HTTP       = "$portHttp"
$env:PORT_HTTPS      = "$portHttps"
$env:ADVERTISE_ADDR  = $advertiseAddr
$env:DOKPLOY_VERSION = $dokployVersion

docker stack deploy -c $composeFile dokploy
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Failed to deploy the stack." -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Stack deployed." -ForegroundColor Green

# --------------------------------------------------
# 7. Wait and show status
# --------------------------------------------------
Write-Host ""
Write-Host "Waiting 15 seconds for services to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

Write-Host ""
Write-Host "Service status:" -ForegroundColor Blue
docker stack services dokploy

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Dokploy is starting!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Dashboard:  http://localhost:$portDashboard" -ForegroundColor Yellow
Write-Host ""
Write-Host "  If the dashboard is not ready yet, wait a few"
Write-Host "  more seconds and try again."
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Blue
Write-Host "  docker stack services dokploy              # Check service status"
Write-Host "  docker service logs dokploy_dokploy -f     # View Dokploy logs"
Write-Host "  docker stack rm dokploy                    # Remove the stack"
Write-Host "  .\teardown.ps1                             # Full cleanup"
Write-Host ""

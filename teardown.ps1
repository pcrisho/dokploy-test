# ==============================================================================
# Dokploy Local Test Environment - Teardown Script (PowerShell)
# ==============================================================================
# Removes the Dokploy stack, secrets, network, and optionally volumes.
# Usage: .\teardown.ps1
# ==============================================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Blue
Write-Host " Dokploy Teardown" -ForegroundColor Blue
Write-Host "========================================" -ForegroundColor Blue
Write-Host ""

# 1. Remove the stack
Write-Host "[...] Removing Dokploy stack..." -ForegroundColor Blue
docker stack rm dokploy 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Stack removed." -ForegroundColor Green
} else {
    Write-Host "[SKIP] Stack was not running." -ForegroundColor Yellow
}

# Wait for services to drain
Write-Host "[...] Waiting for services to drain..." -ForegroundColor Blue
Start-Sleep -Seconds 10

# 2. Remove Docker secret
Write-Host "[...] Removing Docker secrets..." -ForegroundColor Blue
docker secret rm dokploy_postgres_password 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Secret removed." -ForegroundColor Green
} else {
    Write-Host "[SKIP] Secret not found." -ForegroundColor Yellow
}

# 3. Remove network
Write-Host "[...] Removing network..." -ForegroundColor Blue
docker network rm dokploy-network 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Network removed." -ForegroundColor Green
} else {
    Write-Host "[SKIP] Network not found or still in use." -ForegroundColor Yellow
}

# 4. Optionally remove volumes
Write-Host ""
$reply = Read-Host "Also remove all data volumes (postgres, redis, config)? This DELETES all data. (y/N)"
if ($reply -match "^[Yy]$") {
    Write-Host "[...] Removing volumes..." -ForegroundColor Blue
    docker volume rm dokploy_postgres-data dokploy_redis-data dokploy_dokploy-config dokploy_dokploy-docker 2>$null
    Write-Host "[OK] Volumes removed." -ForegroundColor Green
} else {
    Write-Host "[SKIP] Volumes preserved." -ForegroundColor Yellow
}

# 5. Optionally leave Swarm
Write-Host ""
$reply = Read-Host "Leave Docker Swarm? (y/N)"
if ($reply -match "^[Yy]$") {
    docker swarm leave --force 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Left Docker Swarm." -ForegroundColor Green
    } else {
        Write-Host "[SKIP] Not in Swarm." -ForegroundColor Yellow
    }
} else {
    Write-Host "[SKIP] Swarm left active." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Teardown complete." -ForegroundColor Green
Write-Host ""

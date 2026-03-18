#!/bin/bash
# ==============================================================================
# Dokploy Local Test Environment - Setup Script
# ==============================================================================
# Usage: bash setup.sh
# ==============================================================================

set -e

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} Dokploy Local Test Environment Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# --------------------------------------------------
# 0. Load .env file if it exists
# --------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/.env"
    set +a
    echo -e "${GREEN}[OK]${NC} Loaded configuration from .env"
else
    echo -e "${YELLOW}[INFO]${NC} No .env file found, using defaults. Copy .env.example to .env to customize."
fi

# Resolve effective values (env file > env var > default)
PORT_DASHBOARD="${PORT_DASHBOARD:-3000}"
PORT_HTTP="${PORT_HTTP:-80}"
PORT_HTTPS="${PORT_HTTPS:-443}"
ADVERTISE_ADDR="${ADVERTISE_ADDR:-127.0.0.1}"
DOKPLOY_VERSION="${DOKPLOY_VERSION:-latest}"

# --------------------------------------------------
# 1. Check Docker is installed and running
# --------------------------------------------------
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed.${NC}"
    echo "Install Docker Desktop from https://www.docker.com/products/docker-desktop/"
    exit 1
fi

if ! docker info &> /dev/null 2>&1; then
    echo -e "${RED}Error: Docker daemon is not running. Start Docker Desktop first.${NC}"
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Docker is installed and running."

# --------------------------------------------------
# 2. Check port availability
# --------------------------------------------------
check_port() {
    local port=$1
    if command -v ss &> /dev/null; then
        ss -tulnp 2>/dev/null | grep -q ":${port} " && return 1
    elif command -v netstat &> /dev/null; then
        netstat -an 2>/dev/null | grep -q ":${port} " && return 1
    fi
    return 0
}

PORTS_OK=true
for port in "$PORT_HTTP" "$PORT_HTTPS" "$PORT_DASHBOARD"; do
    if ! check_port "$port"; then
        echo -e "${YELLOW}[WARN]${NC} Port $port is already in use."
        PORTS_OK=false
    fi
done

if [ "$PORTS_OK" = true ]; then
    echo -e "${GREEN}[OK]${NC} Required ports (${PORT_HTTP}, ${PORT_HTTPS}, ${PORT_DASHBOARD}) are available."
else
    echo -e "${YELLOW}[WARN]${NC} Some ports are in use. Dokploy may not start correctly."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# --------------------------------------------------
# 3. Initialize Docker Swarm (if not already)
# --------------------------------------------------
if docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo -e "${GREEN}[OK]${NC} Docker Swarm is already active."
else
    echo -e "${BLUE}[...]${NC} Initializing Docker Swarm..."

    ADVERTISE_ADDR="${ADVERTISE_ADDR:-127.0.0.1}"
    docker swarm init --advertise-addr "$ADVERTISE_ADDR" 2>/dev/null || {
        # If it fails with 127.0.0.1, try without specifying address
        docker swarm init 2>/dev/null || {
            echo -e "${RED}Error: Could not initialize Docker Swarm.${NC}"
            echo "Try setting ADVERTISE_ADDR manually:"
            echo "  export ADVERTISE_ADDR=<your-ip>"
            echo "  bash setup.sh"
            exit 1
        }
    }
    echo -e "${GREEN}[OK]${NC} Docker Swarm initialized."
fi

# --------------------------------------------------
# 4. Create overlay network
# --------------------------------------------------
if docker network ls --format '{{.Name}}' | grep -q "^dokploy-network$"; then
    echo -e "${GREEN}[OK]${NC} Network 'dokploy-network' already exists."
else
    docker network create --driver overlay --attachable dokploy-network
    echo -e "${GREEN}[OK]${NC} Overlay network 'dokploy-network' created."
fi

# --------------------------------------------------
# 5. Create Docker secret for Postgres password
# --------------------------------------------------
if docker secret ls --format '{{.Name}}' | grep -q "^dokploy_postgres_password$"; then
    echo -e "${GREEN}[OK]${NC} Secret 'dokploy_postgres_password' already exists."
else
    # Generate random password
    if command -v openssl &> /dev/null; then
        POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    else
        POSTGRES_PASSWORD=$(date +%s%N | sha256sum | base64 | head -c 32 2>/dev/null || echo "dokploy_test_$(date +%s)")
    fi

    echo "$POSTGRES_PASSWORD" | docker secret create dokploy_postgres_password -
    echo -e "${GREEN}[OK]${NC} Docker secret created for Postgres password."
fi

# --------------------------------------------------
# 6. Deploy the stack
# --------------------------------------------------
echo -e "${BLUE}[...]${NC} Deploying Dokploy stack..."

PORT_DASHBOARD="$PORT_DASHBOARD" \
PORT_HTTP="$PORT_HTTP" \
PORT_HTTPS="$PORT_HTTPS" \
ADVERTISE_ADDR="$ADVERTISE_ADDR" \
DOKPLOY_VERSION="$DOKPLOY_VERSION" \
docker stack deploy -c "${SCRIPT_DIR}/docker-compose.yml" dokploy

echo -e "${GREEN}[OK]${NC} Stack deployed."

# --------------------------------------------------
# 7. Wait and show status
# --------------------------------------------------
echo ""
echo -e "${YELLOW}Waiting 15 seconds for services to start...${NC}"
sleep 15

echo ""
echo -e "${BLUE}Service status:${NC}"
docker stack services dokploy

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Dokploy is starting!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "  Dashboard:  ${YELLOW}http://localhost:${PORT_DASHBOARD}${NC}"
echo ""
echo -e "  If the dashboard is not ready yet, wait a few"
echo -e "  more seconds and try again."
echo ""
echo -e "${BLUE}Useful commands:${NC}"
echo "  docker stack services dokploy    # Check service status"
echo "  docker service logs dokploy_dokploy -f   # View Dokploy logs"
echo "  docker stack rm dokploy          # Remove the stack"
echo "  bash teardown.sh                 # Full cleanup"
echo ""

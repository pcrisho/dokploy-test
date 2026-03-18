#!/bin/bash
# ==============================================================================
# Dokploy Local Test Environment - Teardown Script
# ==============================================================================
# Removes the Dokploy stack, secrets, network, and optionally volumes.
# Usage: bash teardown.sh
# ==============================================================================

set -e

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} Dokploy Teardown${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 1. Remove the stack
echo -e "${BLUE}[...]${NC} Removing Dokploy stack..."
docker stack rm dokploy 2>/dev/null && echo -e "${GREEN}[OK]${NC} Stack removed." || echo -e "${YELLOW}[SKIP]${NC} Stack was not running."

# Wait for services to drain
echo -e "${BLUE}[...]${NC} Waiting for services to drain..."
sleep 10

# 2. Remove Docker secret
echo -e "${BLUE}[...]${NC} Removing Docker secrets..."
docker secret rm dokploy_postgres_password 2>/dev/null && echo -e "${GREEN}[OK]${NC} Secret removed." || echo -e "${YELLOW}[SKIP]${NC} Secret not found."

# 3. Remove network
echo -e "${BLUE}[...]${NC} Removing network..."
docker network rm dokploy-network 2>/dev/null && echo -e "${GREEN}[OK]${NC} Network removed." || echo -e "${YELLOW}[SKIP]${NC} Network not found or still in use."

# 4. Optionally remove volumes (data)
echo ""
read -p "Also remove all data volumes (postgres, redis, config)? This DELETES all data. (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}[...]${NC} Removing volumes..."
    docker volume rm dokploy_postgres-data dokploy_redis-data dokploy_dokploy-config dokploy_dokploy-docker 2>/dev/null \
        && echo -e "${GREEN}[OK]${NC} Volumes removed." \
        || echo -e "${YELLOW}[SKIP]${NC} Some volumes not found."
else
    echo -e "${YELLOW}[SKIP]${NC} Volumes preserved."
fi

# 5. Optionally leave Swarm
echo ""
read -p "Leave Docker Swarm? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker swarm leave --force 2>/dev/null && echo -e "${GREEN}[OK]${NC} Left Docker Swarm." || echo -e "${YELLOW}[SKIP]${NC} Not in Swarm."
else
    echo -e "${YELLOW}[SKIP]${NC} Swarm left active."
fi

echo ""
echo -e "${GREEN}Teardown complete.${NC}"
echo ""

#!/bin/bash

set -e

echo "==> Installing K3s in agent mode..."

# Update system
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y curl

# Wait for token file from server
echo "==> Waiting for token file..."
TIMEOUT=60
while [ ! -f "/vagrant_shared/token" ]; do
  sleep 2
  TIMEOUT=$((TIMEOUT - 2))
  if [ "$TIMEOUT" -le 0 ]; then
    echo "ERROR: Token file not found. Server may not be ready."
    exit 1
  fi
  echo "Waiting for token... (${TIMEOUT}s remaining)"
done

# Wait for server to be ready
echo "==> Waiting for K3s server to be available..."
until curl -k https://${SERVER_IP}:6443 &> /dev/null; do
  echo "Waiting for server..."
  sleep 5
done

# Install K3s in agent mode using token file
export K3S_TOKEN_FILE=/vagrant_shared/token
export K3S_URL=https://${SERVER_IP}:6443
curl -sfL https://get.k3s.io | sh -s - agent \
  --node-ip=${WORKER_IP:-192.168.56.111} \
  --flannel-iface=eth1

echo "==> K3s agent installation complete!"

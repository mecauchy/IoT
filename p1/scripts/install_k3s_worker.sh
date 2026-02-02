#!/bin/bash

set -e

echo "==> Installing K3s in agent mode..."

# Update system
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y curl

echo "==> Detecting network interface..."
NETWORK_IFACE=$(ip -o -4 route show to default | awk '{print $5}' | grep -v lo | head -1)
if [ -z "$NETWORK_IFACE" ]; then
  NETWORK_IFACE="eth1"
fi
echo "==> Using network interface: ${NETWORK_IFACE}"

# Wait for token file from server
echo "==> Waiting for token file..."
TIMEOUT=300
while [ ! -f "/vagrant_shared/token" ]; do
  sleep 5
  TIMEOUT=$((TIMEOUT - 5))
  if [ "$TIMEOUT" -le 0 ]; then
    echo "ERROR: Token file not found. Server may not be ready."
    echo "Checking /vagrant_shared contents:"
    ls -la /vagrant_shared/ || echo "Directory not found"
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
  --flannel-iface=${NETWORK_IFACE}

echo "==> K3s agent installation complete!"

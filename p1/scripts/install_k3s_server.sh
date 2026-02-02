#!/bin/bash

set -e

echo "==> Installing K3s in server mode..."

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
echo "==> Server IP: ${SERVER_IP}"

echo "==> Setting up K3s server..."
# Check if token already exists in shared folder
if [ -f "/vagrant_shared/token" ]; then
  K3S_TOKEN=$(cat /vagrant_shared/token)
  echo "==> Using existing token from shared folder"
else
  # Generate random token
  K3S_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 32)
  echo "==> Generated new token"
fi

echo "==> Using token: ${K3S_TOKEN}"
# Install K3s in server mode
curl -sfL https://get.k3s.io | sh -s - server \
  --write-kubeconfig-mode=644 \
  --node-ip=${SERVER_IP} \
  --bind-address=${SERVER_IP} \
  --advertise-address=${SERVER_IP} \
  --flannel-iface=${NETWORK_IFACE} \
  --token=${K3S_TOKEN}

echo "==> K3s server installed."
echo "==> Checking K3s service status..."
sudo systemctl status k3s --no-pager || true

# Wait for K3s to be ready
echo "==> Waiting for K3s to be ready..."
for i in {1..60}; do
  if kubectl get nodes &> /dev/null; then
    echo "==> K3s is ready!"
    break
  fi
  echo "Waiting... ($i/60)"
  sleep 2
done

# Save token to shared folder for worker
echo "==> Saving token to shared folder..."
mkdir -p /vagrant_shared
echo ${K3S_TOKEN} > /vagrant_shared/token
chmod 600 /vagrant_shared/token

echo "==> K3s server installation complete!"
kubectl get nodes

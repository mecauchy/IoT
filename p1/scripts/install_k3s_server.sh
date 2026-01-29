#!/bin/bash

set -e

echo "==> Installing K3s in server mode..."

# Update system
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y curl

# Generate random token
K3S_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 32)

# Install K3s in server mode
curl -sfL https://get.k3s.io | sh -s - server \
  --write-kubeconfig-mode=644 \
  --node-ip=${SERVER_IP} \
  --bind-address=${SERVER_IP} \
  --advertise-address=${SERVER_IP} \
  --flannel-iface=eth1 \
  --token=${K3S_TOKEN}

# Wait for K3s to be ready
echo "==> Waiting for K3s to be ready..."
until kubectl get nodes &> /dev/null; do
  sleep 2
done

# Save token to shared folder for worker
echo "==> Saving token to shared folder..."
mkdir -p /vagrant_shared
echo ${K3S_TOKEN} > /vagrant_shared/token
chmod 600 /vagrant_shared/token

echo "==> K3s server installation complete!"
kubectl get nodes

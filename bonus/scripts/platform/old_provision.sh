#!/usr/bin/env bash
# ============================================================================
# VM1 — k3s + Argo CD + namespaces + application
# Provisions the Kubernetes platform that syncs from GitLab (VM2)
# ============================================================================
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_wait() { echo -e "${YELLOW}[WAIT]${NC} $*"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $*"; }

GITLAB_IP="${GITLAB_IP:-192.168.56.10}"
PLATFORM_IP="${PLATFORM_IP:-192.168.56.20}"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# ============================================================================
# 1. Install k3s (single-node server)
# ============================================================================
if command -v k3s &>/dev/null; then
  log_ok "k3s is already installed."
else
  log_info "Installing k3s..."
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644 \
    --node-ip ${PLATFORM_IP} \
    --bind-address ${PLATFORM_IP} \
    --advertise-address ${PLATFORM_IP}" sh -
  log_ok "k3s installed."
fi

# Wait for node to be ready
log_wait "Waiting for k3s node to become Ready..."
RETRIES=0
until kubectl get nodes 2>/dev/null | grep -q " Ready" || [ $RETRIES -ge 30 ]; do
  sleep 5
  RETRIES=$((RETRIES + 1))
done
kubectl get nodes
log_ok "k3s node is Ready."

# ============================================================================
# 2. Create namespaces (from synced confs/)
# ============================================================================
log_info "Creating namespaces..."

kubectl apply -f /home/vagrant/confs/namespaces/

log_ok "Namespaces created."

# ============================================================================
# 3. Install Argo CD
# ============================================================================
if kubectl get deployment argocd-server -n argocd &>/dev/null; then
  log_ok "Argo CD is already installed."
else
  log_info "Installing Argo CD (server-side apply to avoid large annotations)..."
  kubectl apply --server-side -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  log_wait "Waiting for Argo CD server to be available (up to 5 min)..."
  kubectl wait --for=condition=Available deployment/argocd-server \
    -n argocd --timeout=300s
  log_ok "Argo CD is running."
fi

# ============================================================================
# 4. Expose Argo CD (NodePort for external access)
# ============================================================================
log_info "Patching Argo CD server service to NodePort..."
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "NodePort", "ports": [{"name": "https", "port": 443, "targetPort": 8080, "nodePort": 30443}]}}' \
  2>/dev/null || true

# ============================================================================
# 5. Get Argo CD admin password
# ============================================================================
log_wait "Retrieving Argo CD admin password..."
sleep 5
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "not-yet-available")
echo "${ARGOCD_PASSWORD}" > /home/vagrant/argocd_password.txt
chown vagrant:vagrant /home/vagrant/argocd_password.txt
log_ok "Argo CD password saved to /home/vagrant/argocd_password.txt"

# ============================================================================
# 6. Install Argo CD CLI
# ============================================================================
if command -v argocd &>/dev/null; then
  log_ok "Argo CD CLI already installed."
else
  log_info "Installing Argo CD CLI..."
  curl -sSL -o /usr/local/bin/argocd \
    https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
  chmod +x /usr/local/bin/argocd
  log_ok "Argo CD CLI installed."
fi

# ============================================================================
# 7. Register GitLab repository in Argo CD
# ============================================================================
log_info "Registering GitLab repository in Argo CD..."

kubectl apply -f /home/vagrant/confs/argocd/repo-secret.yaml

log_ok "GitLab repository registered."

# ============================================================================
# 8. Deploy Argo CD Application (from synced confs/)
# ============================================================================
log_info "Creating Argo CD Application..."

kubectl apply -f /home/vagrant/confs/argocd/application.yaml

log_ok "Argo CD Application 'project-mcauchy' created."

# ============================================================================
# 9. Verify
# ============================================================================
log_info "Verification..."
echo ""
echo "--- Nodes ---"
kubectl get nodes -o wide
echo ""
echo "--- Namespaces ---"
kubectl get namespaces
echo ""
echo "--- Argo CD Pods ---"
kubectl get pods -n argocd
echo ""
echo "--- Argo CD Application ---"
kubectl get applications -n argocd 2>/dev/null || echo "(CRDs may still be loading)"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN} Platform VM provisioning complete!${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e " k3s:           kubectl get nodes"
echo -e " Argo CD UI:    https://${PLATFORM_IP}:30443"
echo -e " Argo CD user:  admin"
echo -e " Argo CD pass:  $(cat /home/vagrant/argocd_password.txt 2>/dev/null)"
echo -e " GitLab repo:   http://${GITLAB_IP}/root/iot-manifests"
echo -e " Dev app:       http://${PLATFORM_IP}:30888"
echo -e "${GREEN}================================================================${NC}"
echo ""
echo -e "${YELLOW}GitOps workflow:${NC}"
echo -e "  1. Edit confs/dev/deployment.yml in GitLab (change image tag)"
echo -e "  2. Commit + push to main"
echo -e "  3. Argo CD auto-syncs → app updated in dev namespace"
echo -e ""

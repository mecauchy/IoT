#!/usr/bin/env bash
# ============================================================================
# VM1 — Platform provision script  (idempotent)
# k3s + Argo CD + connects to GitLab repo + verifies end-to-end sync
# ============================================================================
set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_wait() { echo -e "${YELLOW}[WAIT]${NC} $*"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $*"; }

GITLAB_IP="${GITLAB_IP:-192.168.56.10}"
PLATFORM_IP="${PLATFORM_IP:-192.168.56.20}"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

retry() {
  local attempts="$1"; shift
  local sleep_s="$1"; shift
  local n=1
  until "$@"; do
    if [ "$n" -ge "$attempts" ]; then return 1; fi
    n=$((n + 1))
    sleep "$sleep_s"
  done
}

# ============================================================================
# 1. Install k3s
# ============================================================================
if command -v k3s >/dev/null 2>&1; then
  log_ok "k3s already installed."
else
  log_info "Installing k3s..."
  curl -fsSL https://get.k3s.io | INSTALL_K3S_EXEC="\
    --write-kubeconfig-mode 644 \
    --node-ip ${PLATFORM_IP} \
    --bind-address ${PLATFORM_IP} \
    --advertise-address ${PLATFORM_IP} \
    --disable traefik \
    --disable servicelb \
    --kube-controller-manager-arg=node-monitor-grace-period=40s \
    --kubelet-arg=serialize-image-pulls=true" sh -
  log_ok "k3s installed."
fi

log_wait "Waiting for k3s service..."
retry 60 5 systemctl is-active --quiet k3s \
  || { log_err "k3s service not active"; exit 1; }

log_wait "Waiting for Kubernetes API..."
retry 60 5 kubectl get --raw=/readyz >/dev/null 2>&1 \
  || { log_err "Kubernetes API not ready"; exit 1; }

log_wait "Waiting for node Ready..."
retry 60 5 bash -c "kubectl get nodes 2>/dev/null | grep -q ' Ready'" \
  || { log_err "Node not Ready"; exit 1; }
kubectl get nodes -o wide
sleep 3

# ============================================================================
# 2. Namespaces
# ============================================================================
if [ -d /home/vagrant/confs/namespaces ] \
   && ls /home/vagrant/confs/namespaces/*.yaml &>/dev/null; then
  log_info "Applying namespaces..."
  kubectl apply -f /home/vagrant/confs/namespaces/
  log_ok "Namespaces applied."
fi
sleep 2

# ============================================================================
# 3. Install Argo CD
# ============================================================================
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null

if kubectl get deploy argocd-server -n argocd >/dev/null 2>&1; then
  log_ok "Argo CD already installed."
else
  log_info "Installing Argo CD..."
  kubectl apply --server-side -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  log_wait "Waiting for Argo CD core components..."
  retry 120 5 kubectl wait -n argocd --for=condition=Available deploy/argocd-repo-server   --timeout=10s
  retry 120 5 kubectl wait -n argocd --for=condition=Available deploy/argocd-server        --timeout=10s
  retry 120 5 kubectl rollout status -n argocd statefulset/argocd-application-controller   --timeout=10s
  log_ok "Argo CD core components available."
fi
sleep 3

# ============================================================================
# 4. Expose Argo CD via NodePort
# ============================================================================
log_info "Patching Argo CD server service to NodePort 30443..."
kubectl patch svc argocd-server -n argocd --type merge \
  -p '{"spec":{"type":"NodePort","ports":[{"name":"https","port":443,"targetPort":8080,"nodePort":30443}]}}' \
  >/dev/null 2>&1 || true

# ============================================================================
# 5. Retrieve admin password
# ============================================================================
log_wait "Retrieving Argo CD admin password..."
retry 60 5 bash -c "kubectl -n argocd get secret argocd-initial-admin-secret >/dev/null 2>&1" || true
ARGOCD_PASSWORD="$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)"
echo "${ARGOCD_PASSWORD:-not-yet-available}" > /home/vagrant/argocd_password.txt
chown vagrant:vagrant /home/vagrant/argocd_password.txt
chmod 600 /home/vagrant/argocd_password.txt
log_ok "Argo CD password saved."

# ============================================================================
# 6. Wait for GitLab to be reachable
# ============================================================================
log_wait "Waiting for GitLab at http://${GITLAB_IP} ..."
retry 90 10 curl -sf "http://${GITLAB_IP}/-/health" -o /dev/null \
  || { log_err "GitLab not reachable from platform-vm"; exit 1; }
log_ok "GitLab is reachable."

# Verify the repo actually exists
log_wait "Waiting for GitLab repo root/iot-manifests..."
retry 30 10 bash -c "curl -sf 'http://${GITLAB_IP}/api/v4/projects/root%2Fiot-manifests' | grep -q '\"id\"'" \
  || { log_err "GitLab repo root/iot-manifests not found"; exit 1; }
log_ok "GitLab repo root/iot-manifests exists."

# ============================================================================
# 7. Register GitLab repo in Argo CD
# ============================================================================
if [ -f /home/vagrant/confs/argocd/repo-secret.yaml ]; then
  log_info "Applying GitLab repo secret..."
  kubectl apply -f /home/vagrant/confs/argocd/repo-secret.yaml
  log_ok "Repo secret applied."
fi

# ============================================================================
# 8. Apply Argo CD Application
# ============================================================================
if [ -f /home/vagrant/confs/argocd/application.yaml ]; then
  log_info "Applying Argo CD Application..."
  kubectl apply -f /home/vagrant/confs/argocd/application.yaml
  log_ok "Application applied."
fi

# ============================================================================
# 9. Wait for Argo CD to sync and workloads to appear in dev
# ============================================================================
log_wait "Waiting for Argo CD to sync the application (up to 5 min)..."
retry 60 5 bash -c \
  "kubectl get application project-mcauchy -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null | grep -q 'Synced'" \
  || log_info "Sync status not yet 'Synced' — Argo CD may still be reconciling."

SYNC_STATUS=$(kubectl get application project-mcauchy -n argocd \
  -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
HEALTH_STATUS=$(kubectl get application project-mcauchy -n argocd \
  -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
log_info "Application sync=${SYNC_STATUS}  health=${HEALTH_STATUS}"

# Wait for the dev deployment to be ready
log_wait "Waiting for app-deployment in dev namespace..."
retry 60 10 kubectl wait -n dev --for=condition=Available deploy/app-deployment --timeout=10s \
  || log_info "Deployment not yet available — may need more time to pull image."

# ============================================================================
# 10. End-to-end verification
# ============================================================================
log_info "=== Verification ==="
echo ""
kubectl get nodes -o wide
echo ""
echo "--- ArgoCD pods ---"
kubectl get pods -n argocd
echo ""
echo "--- ArgoCD applications ---"
kubectl get applications -n argocd -o wide 2>/dev/null || true
echo ""
echo "--- Dev namespace workloads ---"
kubectl get all -n dev 2>/dev/null || true
echo ""

# Quick smoke test: curl the app service
APP_URL="http://${PLATFORM_IP}:30888"
if curl -sf -o /dev/null -w '' "${APP_URL}" 2>/dev/null; then
  log_ok "App responding at ${APP_URL}"
else
  log_info "App at ${APP_URL} not responding yet (may still be pulling image)."
fi

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}Platform VM provisioning complete${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "Argo CD UI:   https://${PLATFORM_IP}:30443"
echo -e "Argo CD user: admin"
echo -e "Argo CD pass: $(cat /home/vagrant/argocd_password.txt 2>/dev/null)"
echo -e "GitLab:       http://${GITLAB_IP}"
echo -e "GitLab repo:  http://${GITLAB_IP}/root/iot-manifests"
echo -e "App (dev):    http://${PLATFORM_IP}:30888"
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}================================================================${NC}"
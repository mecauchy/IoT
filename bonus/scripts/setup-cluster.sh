#!/bin/bash
# =============================================================================
# CLUSTER SETUP SCRIPT
# =============================================================================
# This script creates and configures the k3d cluster with:
# - ArgoCD (via Helm)
# - Namespaces (argocd, gitlab, dev)
#
# GitLab installation is separate due to its complexity and resource needs.
#
# Design principle: IDEMPOTENT
# - Safe to run multiple times
# - Uses helm upgrade --install (creates or updates)
# - Uses kubectl apply (creates or updates)
# - Checks cluster existence before creating
# =============================================================================

set -e  # Exit on any error

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Script directory (for relative paths)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "=============================================="
echo "  IoT Bonus - Cluster Setup"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# CREATE K3D CLUSTER
# -----------------------------------------------------------------------------
create_cluster() {
    if k3d cluster list | grep -q "iot-bonus"; then
        log_ok "Cluster 'iot-bonus' already exists"
        
        # Ensure kubeconfig is set
        k3d kubeconfig merge iot-bonus --kubeconfig-switch-context
    else
        log_info "Creating k3d cluster 'iot-bonus'..."
        
        k3d cluster create --config "$PROJECT_DIR/k3d-config.yaml"
        
        log_ok "Cluster created successfully"
    fi

    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=120s
    log_ok "Cluster is ready"
}

# -----------------------------------------------------------------------------
# CREATE NAMESPACES
# -----------------------------------------------------------------------------
create_namespaces() {
    log_info "Creating namespaces..."
    
    # Using apply is idempotent (creates or updates)
    kubectl apply -f "$PROJECT_DIR/confs/namespaces.yaml"
    
    log_ok "Namespaces created"
}

# -----------------------------------------------------------------------------
# INSTALL ARGO CD
# -----------------------------------------------------------------------------
install_argocd() {
    log_info "Adding ArgoCD Helm repository..."
    
    # Add repo (idempotent)
    helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
    helm repo update
    
    log_info "Installing ArgoCD via Helm..."
    
    # helm upgrade --install is idempotent
    # - If release doesn't exist: install
    # - If release exists: upgrade
    helm upgrade --install argocd argo/argo-cd \
        --namespace argocd \
        --values "$PROJECT_DIR/helm-values/argocd-values.yaml" \
        --wait \
        --timeout 5m
    
    log_ok "ArgoCD installed successfully"
    
    # Wait for ArgoCD to be ready
    log_info "Waiting for ArgoCD server to be ready..."
    kubectl wait --for=condition=Available deployment/argocd-server \
        -n argocd --timeout=300s
    
    # Get initial admin password
    log_info "Getting ArgoCD admin password..."
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "Password not found")
    
    echo ""
    log_ok "ArgoCD is ready!"
    echo ""
    echo "  ArgoCD UI: http://localhost:8080"
    echo "  Username:  admin"
    echo "  Password:  $ARGOCD_PASSWORD"
    echo ""
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    # Check prerequisites
    for cmd in docker k3d kubectl helm; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "$cmd is not installed. Run: make install-tools"
            exit 1
        fi
    done

    create_cluster
    create_namespaces
    install_argocd

    echo ""
    echo "=============================================="
    log_ok "Cluster setup complete!"
    echo "=============================================="
    echo ""
    echo "Next steps:"
    echo "  1. Run: make install-gitlab"
    echo "  2. Create repository in GitLab"
    echo "  3. Push app-chart to GitLab"
    echo "  4. Run: make deploy-app"
    echo ""
}

main "$@"

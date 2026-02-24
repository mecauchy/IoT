#!/bin/bash
# =============================================================================
# GITLAB INSTALLATION SCRIPT
# =============================================================================
# This script installs GitLab CE into the k3d cluster using Helm.
#
# GitLab is resource-intensive. This script:
# - Uses minimal configuration
# - Disables unnecessary components
# - Sets up for local development only
#
# After installation, you need to:
# 1. Get the root password
# 2. Access GitLab UI
# 3. Create a repository for the app chart
# 4. Create an access token for ArgoCD
# =============================================================================

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "=============================================="
echo "  IoT Bonus - GitLab Installation"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# CREATE GITLAB ROOT PASSWORD SECRET
# -----------------------------------------------------------------------------
create_gitlab_secret() {
    log_info "Creating GitLab root password secret..."
    
    # Generate or use fixed password for reproducibility
    GITLAB_ROOT_PASSWORD="iotBonus123!"
    
    # Create secret if it doesn't exist
    if kubectl -n gitlab get secret gitlab-initial-root-password &>/dev/null; then
        log_ok "GitLab root password secret already exists"
    else
        kubectl create secret generic gitlab-initial-root-password \
            --namespace gitlab \
            --from-literal=password="$GITLAB_ROOT_PASSWORD"
        log_ok "GitLab root password secret created"
    fi
    
    echo ""
    echo "  GitLab root password: $GITLAB_ROOT_PASSWORD"
    echo ""
}

# -----------------------------------------------------------------------------
# INSTALL GITLAB
# -----------------------------------------------------------------------------
install_gitlab() {
    log_info "Adding GitLab Helm repository..."
    
    helm repo add gitlab https://charts.gitlab.io/ 2>/dev/null || true
    helm repo update
    
    log_info "Installing GitLab CE (this may take 5-10 minutes)..."
    log_warn "GitLab requires significant resources. Be patient."
    
    # Install GitLab
    helm upgrade --install gitlab gitlab/gitlab \
        --namespace gitlab \
        --values "$PROJECT_DIR/helm-values/gitlab-values.yaml" \
        --timeout 15m \
        --wait
    
    log_ok "GitLab Helm release installed"
}

# -----------------------------------------------------------------------------
# CREATE GITLAB SERVICE FOR NODEPORT ACCESS
# -----------------------------------------------------------------------------
create_gitlab_nodeport() {
    log_info "Creating GitLab NodePort service for external access..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: gitlab-webservice-nodeport
  namespace: gitlab
spec:
  type: NodePort
  ports:
    - port: 8181
      targetPort: 8181
      nodePort: 30080
      name: http-workhorse
  selector:
    app: webservice
    release: gitlab
EOF

    log_ok "GitLab NodePort service created"
}

# -----------------------------------------------------------------------------
# WAIT FOR GITLAB
# -----------------------------------------------------------------------------
wait_for_gitlab() {
    log_info "Waiting for GitLab pods to be ready..."
    log_warn "This can take 5-10 minutes on first install..."
    
    # Wait for webservice deployment
    kubectl wait --for=condition=Available deployment/gitlab-webservice-default \
        -n gitlab --timeout=600s 2>/dev/null || {
            log_warn "GitLab webservice not ready yet. Check status with:"
            echo "  kubectl get pods -n gitlab"
            return 1
        }
    
    log_ok "GitLab is ready!"
}

# -----------------------------------------------------------------------------
# PRINT ACCESS INFO
# -----------------------------------------------------------------------------
print_access_info() {
    echo ""
    echo "=============================================="
    log_ok "GitLab Installation Complete!"
    echo "=============================================="
    echo ""
    echo "Access GitLab:"
    echo "  URL:      http://gitlab.localhost:8181 (via port-forward)"
    echo "            kubectl port-forward svc/gitlab-webservice-default 8181:8181 -n gitlab"
    echo ""
    echo "  Username: root"
    echo "  Password: iotBonus123!"
    echo ""
    echo "Next steps:"
    echo "  1. Access GitLab and create a new project 'iot-app'"
    echo "  2. Push the app-chart to the repository"
    echo "  3. Create a Personal Access Token for ArgoCD"
    echo "  4. Run: make configure"
    echo ""
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    # Verify cluster is running
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cluster not accessible. Run: make setup-cluster first"
        exit 1
    fi
    
    # Ensure gitlab namespace exists
    kubectl get namespace gitlab &>/dev/null || {
        log_error "Namespace 'gitlab' doesn't exist. Run: make setup-cluster first"
        exit 1
    }
    
    create_gitlab_secret
    install_gitlab
    create_gitlab_nodeport
    wait_for_gitlab
    print_access_info
}

main "$@"

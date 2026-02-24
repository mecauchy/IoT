#!/bin/bash
# =============================================================================
# ARGOCD CONFIGURATION SCRIPT
# =============================================================================
# This script configures ArgoCD to connect to GitLab and deploy the app.
#
# Prerequisites:
# 1. GitLab is installed and running
# 2. Repository 'iot-app' exists in GitLab
# 3. Personal Access Token created in GitLab
#
# This script:
# - Creates the repository secret in ArgoCD
# - Applies the Application CRD
# - Triggers initial sync
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
echo "  IoT Bonus - ArgoCD Configuration"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# GET GITLAB ACCESS TOKEN
# -----------------------------------------------------------------------------
get_gitlab_token() {
    if [ -z "$GITLAB_TOKEN" ]; then
        echo ""
        log_info "GitLab Personal Access Token required for ArgoCD"
        echo ""
        echo "To create a token in GitLab:"
        echo "  1. Go to User Settings > Access Tokens"
        echo "  2. Create token with 'read_repository' scope"
        echo "  3. Copy the token value"
        echo ""
        read -p "Enter GitLab Personal Access Token: " GITLAB_TOKEN
    fi
    
    if [ -z "$GITLAB_TOKEN" ]; then
        log_error "No token provided"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# GET GITLAB INTERNAL URL
# -----------------------------------------------------------------------------
get_gitlab_url() {
    # Get GitLab service URL (internal cluster URL)
    GITLAB_SVC=$(kubectl get svc -n gitlab -l app=webservice -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "gitlab-webservice-default")
    GITLAB_URL="http://${GITLAB_SVC}.gitlab.svc.cluster.local:8181"
    
    log_info "GitLab internal URL: $GITLAB_URL"
}

# -----------------------------------------------------------------------------
# CREATE REPOSITORY SECRET
# -----------------------------------------------------------------------------
create_repo_secret() {
    log_info "Creating ArgoCD repository secret..."
    
    # Delete existing secret if present
    kubectl delete secret gitlab-repo-creds -n argocd 2>/dev/null || true
    
    # Create new secret
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-repo-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: ${GITLAB_URL}/root/iot-app.git
  username: root
  password: ${GITLAB_TOKEN}
  insecure: "true"
EOF

    log_ok "Repository secret created"
}

# -----------------------------------------------------------------------------
# CREATE APPLICATION
# -----------------------------------------------------------------------------
create_application() {
    log_info "Creating ArgoCD Application..."
    
    # Update application.yaml with correct GitLab URL
    sed "s|repoURL:.*|repoURL: ${GITLAB_URL}/root/iot-app.git|g" \
        "$PROJECT_DIR/confs/argocd/application.yaml" | kubectl apply -f -
    
    log_ok "Application created"
}

# -----------------------------------------------------------------------------
# TRIGGER SYNC
# -----------------------------------------------------------------------------
trigger_sync() {
    log_info "Triggering initial sync..."
    
    # Install argocd CLI if available, otherwise skip
    if command -v argocd &>/dev/null; then
        # Get ArgoCD password
        ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
            -o jsonpath="{.data.password}" | base64 -d)
        
        # Login to ArgoCD
        argocd login localhost:8080 --username admin --password "$ARGOCD_PASSWORD" --insecure || true
        
        # Sync application
        argocd app sync playground-app || true
    else
        log_warn "ArgoCD CLI not installed. Sync will happen automatically."
        log_info "Install CLI with: curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64"
    fi
}

# -----------------------------------------------------------------------------
# PRINT STATUS
# -----------------------------------------------------------------------------
print_status() {
    echo ""
    echo "=============================================="
    log_ok "ArgoCD Configuration Complete!"
    echo "=============================================="
    echo ""
    echo "ArgoCD UI: http://localhost:8080"
    echo ""
    echo "Application Status:"
    kubectl get application -n argocd 2>/dev/null || echo "  No applications found"
    echo ""
    echo "To check sync status:"
    echo "  kubectl get application playground-app -n argocd -o yaml"
    echo ""
    echo "To update the app (v1 -> v2):"
    echo "  1. In GitLab, edit helm-chart/values.yaml"
    echo "  2. Change image.tag: \"v1\" to image.tag: \"v2\""
    echo "  3. Commit and push"
    echo "  4. ArgoCD will auto-sync (or click Sync in UI)"
    echo ""
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    get_gitlab_url
    get_gitlab_token
    create_repo_secret
    create_application
    trigger_sync
    print_status
}

main "$@"

#!/bin/bash
# =============================================================================
# CLEANUP SCRIPT
# =============================================================================
# This script removes all resources created by the bonus project:
# - Deletes the k3d cluster
# - Optionally removes Helm repositories
#
# Use this to start fresh or clean up after evaluation.
# =============================================================================

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo ""
echo "=============================================="
echo "  IoT Bonus - Cleanup"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# DELETE CLUSTER
# -----------------------------------------------------------------------------
delete_cluster() {
    if k3d cluster list 2>/dev/null | grep -q "iot-bonus"; then
        log_info "Deleting k3d cluster 'iot-bonus'..."
        k3d cluster delete iot-bonus
        log_ok "Cluster deleted"
    else
        log_ok "Cluster 'iot-bonus' does not exist"
    fi
}

# -----------------------------------------------------------------------------
# CLEAN HELM REPOS (optional)
# -----------------------------------------------------------------------------
clean_helm_repos() {
    if [ "$1" = "--all" ]; then
        log_info "Removing Helm repositories..."
        helm repo remove argo 2>/dev/null || true
        helm repo remove gitlab 2>/dev/null || true
        log_ok "Helm repositories removed"
    fi
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    read -p "Are you sure you want to delete the cluster? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        delete_cluster
        clean_helm_repos "$1"
        
        echo ""
        log_ok "Cleanup complete!"
        echo ""
    else
        log_warn "Cleanup cancelled"
    fi
}

main "$@"

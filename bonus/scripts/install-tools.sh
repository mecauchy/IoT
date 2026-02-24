#!/bin/bash
# =============================================================================
# TOOL INSTALLATION SCRIPT
# =============================================================================
# This script installs all required tools for the IoT Bonus project:
# - Docker: Container runtime for k3d
# - k3d: Kubernetes distribution that runs in Docker
# - kubectl: Kubernetes CLI
# - Helm: Kubernetes package manager
#
# Design principle: IDEMPOTENT
# - Safe to run multiple times
# - Checks if tools exist before installing
# - Uses -q flags for quieter output
# =============================================================================

set -e  # Exit on any error

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'  # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "=============================================="
echo "  IoT Bonus - Tool Installation"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# DOCKER
# -----------------------------------------------------------------------------
install_docker() {
    if command -v docker &> /dev/null; then
        log_ok "Docker is already installed: $(docker --version)"
    else
        log_info "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        rm get-docker.sh
        log_ok "Docker installed successfully"
    fi

    # Add user to docker group (avoids needing sudo)
    if groups "$USER" | grep -q "\bdocker\b"; then
        log_ok "User $USER is already in docker group"
    else
        log_info "Adding $USER to docker group..."
        sudo usermod -aG docker "$USER"
        log_warn "You may need to log out and back in for docker group to take effect"
    fi

    # Start docker service if not running
    if ! sudo systemctl is-active --quiet docker; then
        log_info "Starting Docker service..."
        sudo systemctl start docker
        sudo systemctl enable docker
    fi
}

# -----------------------------------------------------------------------------
# K3D
# -----------------------------------------------------------------------------
install_k3d() {
    if command -v k3d &> /dev/null; then
        log_ok "k3d is already installed: $(k3d --version)"
    else
        log_info "Installing k3d..."
        curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
        log_ok "k3d installed successfully"
    fi
}

# -----------------------------------------------------------------------------
# KUBECTL
# -----------------------------------------------------------------------------
install_kubectl() {
    if command -v kubectl &> /dev/null; then
        log_ok "kubectl is already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
    else
        log_info "Installing kubectl..."
        
        # Get latest stable version
        KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
        
        # Download kubectl
        curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
        
        # Install kubectl
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
        
        log_ok "kubectl installed successfully"
    fi

    # Setup kubectl alias
    if grep -q "alias k='kubectl'" ~/.bashrc 2>/dev/null; then
        log_ok "Alias 'k' already configured"
    else
        log_info "Adding kubectl alias 'k' to ~/.bashrc..."
        echo "alias k='kubectl'" >> ~/.bashrc
    fi
}

# -----------------------------------------------------------------------------
# HELM
# -----------------------------------------------------------------------------
install_helm() {
    if command -v helm &> /dev/null; then
        log_ok "Helm is already installed: $(helm version --short)"
    else
        log_info "Installing Helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
        log_ok "Helm installed successfully"
    fi
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    install_docker
    install_k3d
    install_kubectl
    install_helm

    echo ""
    echo "=============================================="
    log_ok "All tools installed successfully!"
    echo "=============================================="
    echo ""
    log_warn "If this is your first time, please run:"
    echo "    newgrp docker"
    echo "  or log out and back in to apply docker group"
    echo ""
}

main "$@"

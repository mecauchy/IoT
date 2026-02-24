# =============================================================================
# IoT BONUS - MAKEFILE
# =============================================================================
# This Makefile provides convenient shortcuts for all operations.
#
# Usage:
#   make <target>
#
# Main workflow:
#   1. make install-tools   # Install Docker, k3d, kubectl, Helm
#   2. make setup           # Create cluster + install ArgoCD
#   3. make gitlab          # Install GitLab (takes 5-10 min)
#   4. make push-chart      # Push Helm chart to GitLab
#   5. make configure       # Connect ArgoCD to GitLab
#   6. make status          # Check everything is working
#
# Single command:
#   make all                # Run complete setup (except GitLab config)
# =============================================================================

.PHONY: all install-tools setup gitlab configure cleanup status \
        argocd-password gitlab-password push-chart port-forward help

# Default target
.DEFAULT_GOAL := help

# Script directory
SCRIPTS_DIR := scripts
ARGOCD_PORT ?= 18080
GITLAB_PORT ?= 8181

# =============================================================================
# MAIN TARGETS
# =============================================================================

## all: Complete setup (tools + cluster + ArgoCD + GitLab)
all: install-tools setup gitlab
	@echo ""
	@echo "=============================================="
	@echo "  Installation Complete!"
	@echo "=============================================="
	@echo ""
	@echo "Next steps:"
	@echo "  1. Access GitLab: make port-forward-gitlab"
	@echo "  2. Create repo 'iot-app' in GitLab"
	@echo "  3. Push chart: make push-chart"
	@echo "  4. Configure: make configure"
	@echo ""

## install-tools: Install Docker, k3d, kubectl, Helm
install-tools:
	@chmod +x $(SCRIPTS_DIR)/install-tools.sh
	@$(SCRIPTS_DIR)/install-tools.sh

## setup: Create k3d cluster and install ArgoCD
setup:
	@chmod +x $(SCRIPTS_DIR)/setup-cluster.sh
	@$(SCRIPTS_DIR)/setup-cluster.sh

## gitlab: Install GitLab CE in the cluster
gitlab:
	@chmod +x $(SCRIPTS_DIR)/install-gitlab.sh
	@$(SCRIPTS_DIR)/install-gitlab.sh

## configure: Configure ArgoCD to connect to GitLab
configure:
	@chmod +x $(SCRIPTS_DIR)/configure-argocd.sh
	@$(SCRIPTS_DIR)/configure-argocd.sh

## cleanup: Delete cluster and clean up resources
cleanup:
	@chmod +x $(SCRIPTS_DIR)/cleanup.sh
	@$(SCRIPTS_DIR)/cleanup.sh

# =============================================================================
# UTILITY TARGETS
# =============================================================================

## status: Show status of all components
status:
	@echo ""
	@echo "=== Cluster ===" 
	@k3d cluster list 2>/dev/null || echo "No clusters found"
	@echo ""
	@echo "=== Nodes ==="
	@kubectl get nodes 2>/dev/null || echo "Cluster not accessible"
	@echo ""
	@echo "=== Namespaces ==="
	@kubectl get namespaces 2>/dev/null | grep -E "NAME|argocd|gitlab|dev" || true
	@echo ""
	@echo "=== ArgoCD Pods ==="
	@kubectl get pods -n argocd 2>/dev/null || echo "ArgoCD not installed"
	@echo ""
	@echo "=== GitLab Pods ==="
	@kubectl get pods -n gitlab 2>/dev/null || echo "GitLab not installed"
	@echo ""
	@echo "=== Dev Pods ==="
	@kubectl get pods -n dev 2>/dev/null || echo "No app deployed"
	@echo ""
	@echo "=== ArgoCD Applications ==="
	@kubectl get applications -n argocd 2>/dev/null || echo "No applications"

## argocd-password: Get ArgoCD admin password
argocd-password:
	@echo "ArgoCD Admin Password:"
	@kubectl -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d && echo ""

## gitlab-password: Get GitLab root password
gitlab-password:
	@echo "GitLab Root Password: iotBonus123!"

## port-forward-gitlab: Forward GitLab port for browser access
port-forward-gitlab:
	@echo "GitLab will be available at: http://gitlab.localhost:$(GITLAB_PORT)"
	@echo "Press Ctrl+C to stop"
	@kubectl port-forward svc/gitlab-webservice-default $(GITLAB_PORT):8181 -n gitlab

## port-forward-argocd: Forward ArgoCD port for browser access
port-forward-argocd:
	@echo "ArgoCD will be available at: http://localhost:$(ARGOCD_PORT)"
	@echo "Press Ctrl+C to stop"
	@kubectl port-forward svc/argocd-server $(ARGOCD_PORT):80 -n argocd

## push-chart: Push the Helm chart to GitLab (interactive)
push-chart:
	@echo ""
	@echo "To push the Helm chart to GitLab:"
	@echo ""
	@echo "1. Create a new project 'iot-app' in GitLab (http://gitlab.localhost:$(GITLAB_PORT))"
	@echo ""
	@echo "2. Clone and push the chart:"
	@echo "   cd /tmp"
	@echo "   git clone http://gitlab.localhost:$(GITLAB_PORT)/root/iot-app.git"
	@echo "   cp -r $(PWD)/app-chart/* iot-app/"
	@echo "   cd iot-app"
	@echo "   git add ."
	@echo "   git commit -m 'Initial commit - playground app v1'"
	@echo "   git push origin main"
	@echo ""
	@echo "3. Then run: make configure"
	@echo ""

## app-logs: Show logs from the deployed application
app-logs:
	@kubectl logs -l app=playground -n dev --tail=50 -f 2>/dev/null || \
		echo "No app pods found. Is the application deployed?"

## app-version: Show current deployed version
app-version:
	@echo "Current deployed image:"
	@kubectl get deployment -n dev -o jsonpath='{.items[*].spec.template.spec.containers[*].image}' 2>/dev/null || \
		echo "No deployment found"
	@echo ""

## sync: Force ArgoCD to sync the application
sync:
	@echo "Forcing ArgoCD sync..."
	@kubectl patch application playground-app -n argocd \
		--type merge -p '{"operation": {"sync": {}}}' 2>/dev/null || \
		echo "Application not found or sync failed"

## test-app: Test the deployed application
test-app:
	@echo "Testing application on http://localhost:8888..."
	@curl -s http://localhost:8888 2>/dev/null || echo "Application not accessible"

# =============================================================================
# HELP
# =============================================================================

## help: Show this help message
help:
	@echo ""
	@echo "IoT Bonus - Makefile Targets"
	@echo "============================"
	@echo ""
	@echo "MAIN WORKFLOW:"
	@grep -E '^## ' $(MAKEFILE_LIST) | grep -E '(install-tools|setup|gitlab|configure|all):' | \
		sed 's/## /  /' | sed 's/: /:\t/'
	@echo ""
	@echo "UTILITY:"
	@grep -E '^## ' $(MAKEFILE_LIST) | grep -vE '(install-tools|setup|gitlab|configure|all|cleanup):' | \
		grep -vE 'help:' | sed 's/## /  /' | sed 's/: /:\t/'
	@echo ""
	@echo "CLEANUP:"
	@grep -E '^## cleanup:' $(MAKEFILE_LIST) | sed 's/## /  /' | sed 's/: /:\t/'
	@echo ""

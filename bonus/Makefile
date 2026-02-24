# ============================================================================
# Inception of Things — Bonus Part
# Orchestrates sequential VM startup to avoid OOM on the host.
#   1. gitlab-vm   (4 GB) — GitLab CE + repo setup
#   2. platform-vm (2 GB) — k3s + Argo CD + syncs from GitLab
# ============================================================================

VAGRANT     := vagrant
GITLAB_VM   := gitlab-vm
PLATFORM_VM := platform-vm
GITLAB_IP   := 192.168.56.10
PLATFORM_IP := 192.168.56.20

# Stamp files track what has already been done (idempotent re-runs).
STAMP_DIR   := .stamps
STAMP_GITLAB   := $(STAMP_DIR)/gitlab-up
STAMP_PLATFORM := $(STAMP_DIR)/platform-up

.PHONY: all gitlab platform clean destroy status test re help

# ── Default target ──────────────────────────────────────────────────────────
all: gitlab platform ## Full deploy: gitlab-vm then platform-vm (sequential)

# ── GitLab VM ───────────────────────────────────────────────────────────────
gitlab: $(STAMP_GITLAB) ## Bring up gitlab-vm only

$(STAMP_GITLAB):
	@echo "\n======  Stage 1/2 — gitlab-vm  ======"
	@echo "  RAM required : 4 GB"
	@echo "  This will install GitLab CE, create the repo, and push manifests."
	@echo ""
	$(VAGRANT) up $(GITLAB_VM)
	@echo "\n--- Verifying GitLab health ---"
	@for i in $$(seq 1 30); do \
		code=$$(curl -sf -o /dev/null -w '%{http_code}' http://$(GITLAB_IP)/-/health 2>/dev/null); \
		if [ "$$code" = "200" ]; then echo "GitLab healthy (HTTP $$code)"; break; fi; \
		echo "  waiting… (attempt $$i/30)"; sleep 10; \
	done
	@mkdir -p $(STAMP_DIR)
	@touch $@
	@echo "\n======  gitlab-vm ready  ======\n"

# ── Platform VM ─────────────────────────────────────────────────────────────
platform: $(STAMP_PLATFORM) ## Bring up platform-vm (requires gitlab-vm)

$(STAMP_PLATFORM): $(STAMP_GITLAB)
	@echo "\n======  Stage 2/2 — platform-vm  ======"
	@echo "  RAM required : 2 GB"
	@echo "  This will install k3s, Argo CD, and sync from GitLab."
	@echo ""
	$(VAGRANT) up $(PLATFORM_VM)
	@mkdir -p $(STAMP_DIR)
	@touch $@
	@echo "\n======  platform-vm ready  ======\n"

# ── Status ──────────────────────────────────────────────────────────────────
status: ## Show VM status, host RAM, and service URLs
	@echo "--- Vagrant status ---"
	@$(VAGRANT) status
	@echo ""
	@echo "--- Host memory ---"
	@free -h | head -2
	@echo ""
	@echo "--- VirtualBox running VMs ---"
	@VBoxManage list runningvms 2>/dev/null || echo "(none)"
	@echo ""
	@echo "--- Service URLs ---"
	@printf "GitLab:   http://$(GITLAB_IP)       "; \
	  curl -sf -o /dev/null -w "(HTTP %{http_code})\n" http://$(GITLAB_IP)/ 2>/dev/null || echo "(unreachable)"
	@printf "ArgoCD:   https://$(PLATFORM_IP):30443  "; \
	  curl -ksf -o /dev/null -w "(HTTP %{http_code})\n" https://$(PLATFORM_IP):30443/ 2>/dev/null || echo "(unreachable)"
	@printf "App:      http://$(PLATFORM_IP):30888   "; \
	  curl -sf -o /dev/null -w "(HTTP %{http_code})\n" http://$(PLATFORM_IP):30888/ 2>/dev/null || echo "(unreachable)"

# ── Test the full pipeline ──────────────────────────────────────────────────
test: ## Run end-to-end tests on the running VMs
	@echo "=== Testing GitLab ==="
	@curl -sf http://$(GITLAB_IP)/-/health && echo " [OK] GitLab health" || echo " [FAIL] GitLab health"
	@curl -sf "http://$(GITLAB_IP)/api/v4/projects/root%2Fiot-manifests" | \
	  python3 -c "import sys,json; p=json.load(sys.stdin); print(f' [OK] Repo: {p[\"path_with_namespace\"]} (id={p[\"id\"]})')" \
	  2>/dev/null || echo " [FAIL] Repo root/iot-manifests not found"
	@echo ""
	@echo "=== Testing Argo CD ==="
	@curl -ksf https://$(PLATFORM_IP):30443/ -o /dev/null && echo " [OK] ArgoCD UI" || echo " [FAIL] ArgoCD UI"
	@$(VAGRANT) ssh $(PLATFORM_VM) -c "\
	  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; \
	  echo ' ArgoCD app status:'; \
	  kubectl get application project-mcauchy -n argocd -o jsonpath='  sync={.status.sync.status}  health={.status.health.status}' 2>/dev/null; echo; \
	  echo ''; \
	  echo ' Dev namespace pods:'; \
	  kubectl get pods -n dev 2>/dev/null || echo '  (none)'; \
	  echo ''; \
	  echo ' Dev namespace services:'; \
	  kubectl get svc -n dev 2>/dev/null || echo '  (none)'; \
	" 2>/dev/null
	@echo ""
	@echo "=== Testing App endpoint ==="
	@curl -sf http://$(PLATFORM_IP):30888/ -o /dev/null \
	  && echo " [OK] App at http://$(PLATFORM_IP):30888" \
	  || echo " [WARN] App not responding yet (image may still be pulling)"

# ── Rebuild from scratch ────────────────────────────────────────────────────
re: destroy all ## Full rebuild: destroy everything then deploy

# ── Cleanup ─────────────────────────────────────────────────────────────────
clean: ## Remove stamp files (keeps VMs running)
	rm -rf $(STAMP_DIR)

destroy: ## Destroy all VMs and remove stamps
	-$(VAGRANT) destroy $(PLATFORM_VM) -f 2>/dev/null
	-$(VAGRANT) destroy $(GITLAB_VM) -f 2>/dev/null
	rm -rf $(STAMP_DIR)

# ── SSH shortcuts ───────────────────────────────────────────────────────────
ssh-gitlab: ## SSH into gitlab-vm
	$(VAGRANT) ssh $(GITLAB_VM)

ssh-platform: ## SSH into platform-vm
	$(VAGRANT) ssh $(PLATFORM_VM)

# ── Help ────────────────────────────────────────────────────────────────────
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

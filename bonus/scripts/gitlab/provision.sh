#!/usr/bin/env bash
# ============================================================================
# VM2 — GitLab CE + GitLab Runner provision script
# Installs GitLab via official apt repository (package method)
# Data persists on the VM disk: /var/opt/gitlab, /etc/gitlab
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
EXTERNAL_URL="http://${GITLAB_IP}"

# ============================================================================
# 1. System packages
# ============================================================================
log_info "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -yq
apt-get install -yq curl ca-certificates tzdata perl openssh-server \
  postfix apt-transport-https gnupg2

# ============================================================================
# 2. Install GitLab CE
# ============================================================================
if command -v gitlab-ctl &>/dev/null; then
  log_ok "GitLab is already installed."
else
  log_info "Adding GitLab repository..."
  curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash

  log_info "Installing GitLab CE (EXTERNAL_URL=${EXTERNAL_URL})..."
  EXTERNAL_URL="${EXTERNAL_URL}" apt-get install -yq gitlab-ce
fi

# ============================================================================
# 3. Configure GitLab
# ============================================================================
log_info "Configuring GitLab (external_url = ${EXTERNAL_URL})..."

# Ensure external_url is set correctly
sed -i "s|^external_url.*|external_url '${EXTERNAL_URL}'|" /etc/gitlab/gitlab.rb

# Reduce memory footprint for a VM lab environment
grep -q "puma\['worker_processes'\]" /etc/gitlab/gitlab.rb && \
  sed -i "s|^.*puma\['worker_processes'\].*|puma['worker_processes'] = 2|" /etc/gitlab/gitlab.rb || \
  echo "puma['worker_processes'] = 2" >> /etc/gitlab/gitlab.rb

grep -q "sidekiq\['concurrency'\]" /etc/gitlab/gitlab.rb && \
  sed -i "s|^.*sidekiq\['concurrency'\].*|sidekiq['concurrency'] = 5|" /etc/gitlab/gitlab.rb || \
  echo "sidekiq['concurrency'] = 5" >> /etc/gitlab/gitlab.rb

grep -q "postgresql\['shared_buffers'\]" /etc/gitlab/gitlab.rb && \
  sed -i "s|^.*postgresql\['shared_buffers'\].*|postgresql['shared_buffers'] = \"256MB\"|" /etc/gitlab/gitlab.rb || \
  echo "postgresql['shared_buffers'] = \"256MB\"" >> /etc/gitlab/gitlab.rb

# Apply configuration
gitlab-ctl reconfigure

# ============================================================================
# 4. Wait for GitLab to be fully ready
# ============================================================================
log_wait "Waiting for GitLab to start (this may take a few minutes)..."
MAX_RETRIES=60
RETRY=0
until curl -sf "${EXTERNAL_URL}/-/readiness" &>/dev/null || [ $RETRY -ge $MAX_RETRIES ]; do
  sleep 10
  RETRY=$((RETRY + 1))
  echo -ne "  Attempt ${RETRY}/${MAX_RETRIES}...\r"
done

if [ $RETRY -ge $MAX_RETRIES ]; then
  log_err "GitLab did not become ready in time. Check 'gitlab-ctl status'."
else
  log_ok "GitLab is up and running at ${EXTERNAL_URL}"
fi

# ============================================================================
# 5. Retrieve initial root password
# ============================================================================
if [ -f /etc/gitlab/initial_root_password ]; then
  ROOT_PASSWORD=$(grep 'Password:' /etc/gitlab/initial_root_password | awk '{print $2}')
  log_ok "GitLab initial root password: ${ROOT_PASSWORD}"
  echo "${ROOT_PASSWORD}" > /home/vagrant/gitlab_root_password.txt
  chown vagrant:vagrant /home/vagrant/gitlab_root_password.txt
  log_info "Password saved to /home/vagrant/gitlab_root_password.txt"
else
  log_info "Initial root password file not found (already consumed or custom password set)."
fi

# ============================================================================
# 6. Install GitLab Runner
# ============================================================================
if command -v gitlab-runner &>/dev/null; then
  log_ok "GitLab Runner is already installed."
else
  log_info "Installing GitLab Runner..."
  curl -fsSL https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | bash
  apt-get install -yq gitlab-runner
  log_ok "GitLab Runner installed."
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN} GitLab VM provisioning complete!${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e " GitLab URL:      ${EXTERNAL_URL}"
echo -e " Username:        root"
if [ -f /home/vagrant/gitlab_root_password.txt ]; then
  echo -e " Password:        $(cat /home/vagrant/gitlab_root_password.txt)"
fi
echo -e ""
echo -e " Next steps:"
echo -e "   1. Log in to GitLab at ${EXTERNAL_URL}"
echo -e "   2. Create a project (e.g. root/iot-manifests)"
echo -e "   3. Push your manifests from your local machine"
echo -e "   4. Configure Argo CD on platform-vm to point to this repo"
echo -e "${GREEN}================================================================${NC}"

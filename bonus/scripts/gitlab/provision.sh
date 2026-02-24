#!/usr/bin/env bash
# ============================================================================
# VM2 — GitLab CE + GitLab Runner provision script  (idempotent)
# Installs GitLab, creates the iot-manifests repo, and pushes initial
# manifests so that Argo CD on the platform-vm can sync immediately.
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
# Deterministic password — makes re-provisioning idempotent
ROOT_PASSWORD="Passw0rd!"
TOKEN_NAME="vagrant-provision"
PROJECT_NAME="iot-manifests"

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
# 1. System packages
# ============================================================================
log_info "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
dpkg --configure -a 2>/dev/null || true
apt-get install -f -yq 2>/dev/null || true
apt-get update -yq
apt-get install -yq curl ca-certificates tzdata perl openssh-server \
  postfix apt-transport-https gnupg2 git

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
# 3. Configure GitLab  (idempotent — always re-apply)
# ============================================================================
log_info "Configuring GitLab (external_url = ${EXTERNAL_URL})..."

sed -i "s|^external_url.*|external_url '${EXTERNAL_URL}'|" /etc/gitlab/gitlab.rb

# Reduce memory footprint for a lab VM
for setting in \
  "puma['worker_processes'] = 2" \
  "sidekiq['concurrency'] = 5" \
  "postgresql['shared_buffers'] = \"256MB\"" \
; do
  key="${setting%%=*}"
  key="${key// /}"  # strip spaces for grep
  grep -q "${key}" /etc/gitlab/gitlab.rb \
    && sed -i "s|^.*${key}.*|${setting}|" /etc/gitlab/gitlab.rb \
    || echo "${setting}" >> /etc/gitlab/gitlab.rb
done

gitlab-ctl reconfigure

# ============================================================================
# 4. Wait for GitLab to be fully ready
# ============================================================================
log_wait "Waiting for GitLab to start (this may take a few minutes)..."
retry 90 10 curl -sf "${EXTERNAL_URL}/-/health" -o /dev/null \
  || { log_err "GitLab did not become healthy."; gitlab-ctl status; exit 1; }
log_ok "GitLab is healthy at ${EXTERNAL_URL}"

# ============================================================================
# 5. Set deterministic root password (idempotent via gitlab-rails)
# ============================================================================
log_info "Setting root password..."
gitlab-rails runner "
  u = User.find_by_username('root')
  u.password = '${ROOT_PASSWORD}'
  u.password_confirmation = '${ROOT_PASSWORD}'
  u.save!
  puts 'Root password updated.'
" 2>/dev/null || log_info "Password was already set (OK)."
echo "${ROOT_PASSWORD}" > /home/vagrant/gitlab_root_password.txt
chown vagrant:vagrant /home/vagrant/gitlab_root_password.txt
log_ok "Root password: ${ROOT_PASSWORD}"

# ============================================================================
# 6. Create a Personal Access Token (idempotent)
# ============================================================================
log_info "Creating Personal Access Token '${TOKEN_NAME}'..."
PAT=$(gitlab-rails runner "
  u = User.find_by_username('root')
  t = u.personal_access_tokens.find_by(name: '${TOKEN_NAME}')
  if t && !t.revoked? && !t.expired?
    puts t.token
  else
    t&.revoke!
    nt = u.personal_access_tokens.create!(
      name: '${TOKEN_NAME}',
      scopes: [:api, :write_repository, :read_repository],
      expires_at: 1.year.from_now
    )
    puts nt.token
  end
" 2>/dev/null)

if [ -z "${PAT}" ]; then
  log_err "Failed to obtain a Personal Access Token."
  exit 1
fi
echo "${PAT}" > /home/vagrant/gitlab_pat.txt
chown vagrant:vagrant /home/vagrant/gitlab_pat.txt
log_ok "PAT saved to /home/vagrant/gitlab_pat.txt"

# ============================================================================
# 7. Create project root/iot-manifests (idempotent via API)
# ============================================================================
log_info "Ensuring project root/${PROJECT_NAME} exists..."
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" \
  -H "PRIVATE-TOKEN: ${PAT}" \
  "${EXTERNAL_URL}/api/v4/projects/root%2F${PROJECT_NAME}" 2>/dev/null || true)

if [ "${HTTP_CODE}" = "200" ]; then
  log_ok "Project root/${PROJECT_NAME} already exists."
else
  log_info "Creating project root/${PROJECT_NAME}..."
  curl -sf -X POST "${EXTERNAL_URL}/api/v4/projects" \
    -H "PRIVATE-TOKEN: ${PAT}" \
    -d "name=${PROJECT_NAME}&visibility=public&initialize_with_readme=true" \
    -o /dev/null
  log_ok "Project created."
  # Wait for the repo to be ready
  sleep 5
fi

# ============================================================================
# 8. Push manifests into the repo  (idempotent — force-push)
# ============================================================================
log_info "Pushing manifests to root/${PROJECT_NAME}..."
REPO_DIR=$(mktemp -d)
cd "${REPO_DIR}"
git init -b main
git config user.email "vagrant@provision"
git config user.name  "Vagrant Provision"

# Copy manifest tree
mkdir -p confs/dev
cp /home/vagrant/confs/dev/deployment.yml confs/dev/
cp /home/vagrant/confs/dev/service.yml    confs/dev/
if [ -f /home/vagrant/confs/.gitlab-ci.yml ]; then
  cp /home/vagrant/confs/.gitlab-ci.yml .gitlab-ci.yml
fi

git add -A
git commit -m "Initial manifests (provisioned by Vagrant)" --allow-empty

git remote add origin "http://root:${PAT}@${GITLAB_IP}/${PROJECT_NAME}.git" 2>/dev/null \
  || git remote set-url origin "http://root:${PAT}@${GITLAB_IP}/${PROJECT_NAME}.git"
git push -u origin main --force
cd /
rm -rf "${REPO_DIR}"
log_ok "Manifests pushed to ${EXTERNAL_URL}/root/${PROJECT_NAME}"

# ============================================================================
# 9. Install GitLab Runner
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
echo -e " Password:        ${ROOT_PASSWORD}"
echo -e " PAT:             ${PAT:0:15}..."
echo -e " Project:         ${EXTERNAL_URL}/root/${PROJECT_NAME}"
echo -e "${GREEN}================================================================${NC}"

# IoT Bonus - k3d + Helm + GitLab + ArgoCD

## Overview

This bonus implements a complete local GitOps environment using:

- **k3d**: Lightweight Kubernetes (k3s in Docker)
- **Helm**: Kubernetes package manager
- **GitLab CE**: Local Git server (replacing GitHub)
- **ArgoCD**: GitOps continuous delivery tool

The architecture follows GitOps principles:
1. Application configuration is stored in Git (GitLab)
2. ArgoCD watches the repository for changes
3. Changes trigger automatic deployment
4. The cluster state always matches the Git state

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        k3d Cluster                              │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    Namespaces                            │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │   │
│  │  │   argocd    │  │   gitlab    │  │       dev       │   │   │
│  │  │             │  │             │  │                 │   │   │
│  │  │ ArgoCD      │  │ GitLab CE   │  │ playground-app  │   │   │
│  │  │ Server      │──│ (Git repo)  │──│ (Helm release)  │   │   │
│  │  │             │  │             │  │                 │   │   │
│  │  └─────────────┘  └─────────────┘  └─────────────────┘   │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              ▲                                  │
│  Port mappings:              │ GitOps sync                      │
│  - 8080 → ArgoCD UI          │                                  │
│  - 8181 → GitLab             │                                  │
│  - 8888 → Application        │                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

```bash
# 1. Install required tools (Docker, k3d, kubectl, Helm)
make install-tools

# 2. Create cluster and install ArgoCD
make setup

# 3. Install GitLab (takes 5-10 minutes)
make gitlab

# 4. Check status
make status
```

## Step-by-Step Guide

### Step 1: Install Tools

```bash
make install-tools
```

This installs:
- Docker CE
- k3d (k3s in Docker)
- kubectl (Kubernetes CLI)
- Helm 3 (package manager)

### Step 2: Create Cluster

```bash
make setup
```

This creates:
- k3d cluster named `iot-bonus`
- Namespaces: `argocd`, `gitlab`, `dev`
- ArgoCD installation via Helm

Access ArgoCD:
```bash
# Get password
make argocd-password

# Port forward (if needed)
make port-forward-argocd
```

**ArgoCD UI**: http://localhost:8080
- Username: `admin`
- Password: (from `make argocd-password`)

### Step 3: Install GitLab

```bash
make gitlab
```

This installs GitLab CE with minimal configuration.

Access GitLab:
```bash
# Port forward
make port-forward-gitlab
```

**GitLab UI**: http://gitlab.localhost:8181
- Username: `root`
- Password: `iotBonus2024!`

### Step 4: Create GitLab Repository

1. Open http://gitlab.localhost:8181
2. Login with `root` / `iotBonus2024!`
3. Create new project: `iot-app`
4. Make it public (or create access token)

### Step 5: Push Helm Chart to GitLab

```bash
# Clone the empty repo
cd /tmp
git clone http://gitlab.localhost:8181/root/iot-app.git
cd iot-app

# Copy the Helm chart
cp -r /path/to/IoT/bonus/app-chart/* .

# Rename the chart directory if needed
mkdir -p helm-chart
mv Chart.yaml values.yaml templates helm-chart/

# Commit and push
git add .
git commit -m "Initial commit - playground app v1"
git push origin main
```

### Step 6: Create GitLab Access Token

1. In GitLab, go to **User Settings > Access Tokens**
2. Create token with:
   - Name: `argocd`
   - Scopes: `read_repository`
3. Copy the token

### Step 7: Configure ArgoCD

```bash
# Set the token and configure
export GITLAB_TOKEN=<your-token>
make configure
```

Or run interactively:
```bash
make configure
# (you'll be prompted for the token)
```

### Step 8: Verify Deployment

```bash
# Check application status
make status

# Test the application
make test-app

# View current version
make app-version
```

## Updating the Application (v1 → v2)

To demonstrate GitOps, update the application version:

1. In GitLab, edit `helm-chart/values.yaml`
2. Change `image.tag` from `"v1"` to `"v2"`
3. Commit and push

ArgoCD will automatically:
1. Detect the change (within 3 minutes, or use webhook)
2. Sync the new version
3. Deploy v2 of the application

```bash
# Force immediate sync
make sync

# Watch the rollout
kubectl get pods -n dev -w

# Verify new version
make app-version
```

## File Structure

```
bonus/
├── Makefile                    # Convenience commands
├── README.md                   # This file
├── k3d-config.yaml            # k3d cluster configuration
│
├── helm-values/
│   ├── argocd-values.yaml     # ArgoCD Helm values
│   └── gitlab-values.yaml     # GitLab Helm values (minimal)
│
├── confs/
│   ├── namespaces.yaml        # Kubernetes namespaces
│   └── argocd/
│       ├── application.yaml   # ArgoCD Application CRD
│       └── gitlab-repo-secret.yaml  # GitLab credentials
│
├── app-chart/                  # Helm chart (push to GitLab)
│   ├── Chart.yaml
│   ├── values.yaml            # Change image.tag here
│   └── templates/
│       ├── _helpers.tpl
│       ├── deployment.yaml
│       └── service.yaml
│
└── scripts/
    ├── install-tools.sh       # Install Docker, k3d, etc.
    ├── setup-cluster.sh       # Create cluster + ArgoCD
    ├── install-gitlab.sh      # Install GitLab CE
    ├── configure-argocd.sh    # Connect ArgoCD to GitLab
    └── cleanup.sh             # Remove everything
```

## Key Concepts

### Idempotency

All scripts are designed to be **idempotent** (safe to run multiple times):
- `helm upgrade --install` creates or updates
- `kubectl apply` creates or updates
- Scripts check for existing resources before creating

### GitOps Flow

```
Developer → Push to GitLab → ArgoCD detects → Sync to Cluster
                ↑                                    │
                └────────── Desired State ←──────────┘
```

### ArgoCD Sync Policy

The Application CRD configures:
- `automated.prune: true` - Remove deleted resources
- `automated.selfHeal: true` - Revert manual changes
- `syncOptions.CreateNamespace: true` - Auto-create namespace

## Troubleshooting

### ArgoCD can't connect to GitLab

1. Check GitLab is running: `kubectl get pods -n gitlab`
2. Verify the repository secret:
   ```bash
   kubectl get secret gitlab-repo-creds -n argocd -o yaml
   ```
3. Check ArgoCD logs:
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server
   ```

### Application not syncing

1. Check application status:
   ```bash
   kubectl get application playground-app -n argocd -o yaml
   ```
2. Force refresh:
   ```bash
   make sync
   ```

### GitLab pods not starting

GitLab is resource-intensive. Check:
```bash
kubectl describe pods -n gitlab
kubectl get events -n gitlab --sort-by='.lastTimestamp'
```

### Port already in use

```bash
# Find and kill process using the port
sudo lsof -i :8080
sudo kill <PID>
```

## Cleanup

```bash
make cleanup
```

This removes:
- k3d cluster `iot-bonus`
- All namespaces and resources

## Requirements

- Linux (tested on Ubuntu/Debian)
- 8GB+ RAM recommended (GitLab needs ~4GB)
- 20GB+ free disk space
- Docker permissions (user in `docker` group)

## Evaluation Notes

This implementation demonstrates:

1. **Infrastructure as Code**: All resources defined in YAML
2. **GitOps**: Git is the single source of truth
3. **Idempotency**: Safe to rerun all commands
4. **Helm**: Package management for Kubernetes
5. **ArgoCD**: Automated continuous delivery
6. **Local GitLab**: Self-hosted Git server
7. **Proper namespacing**: Logical separation of concerns

## Author

mcauchy - 42 School
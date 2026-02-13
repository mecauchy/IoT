#!/bin/bash

# Arrêt du script au moindre échec
set -e

GREEN='\033[0;32m'
BLUE='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}\t\t\t\bInstallation de l'environnement IoT...\b${NC}\n"

# Installation de Docker
if command -v docker &> /dev/null; then
    echo -e "${GREEN}[OK] Docker est déjà installé. Étape ignorée.${NC}"
else
    echo -e "${BLUE}[ACTION] Installation de Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
fi

if groups $USER | grep -q "\bdocker\b"; then
    echo -e "${GREEN}[OK] L'utilisateur $USER est déjà dans le groupe docker.${NC}"
else
    echo -e "${BLUE}[ACTION] Ajout de l'utilisateur $USER au groupe docker...${NC}"
    sudo usermod -aG docker $USER
fi

# Installation de K3d
if command -v k3d &> /dev/null; then
    echo -e "${GREEN}[OK] K3d est déjà installé. Étape ignorée.${NC}"
else
    echo -e "${BLUE}[ACTION] Installation de K3d...${NC}"
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

# Installation de Kubectl
if command -v kubectl &> /dev/null; then
    echo -e "${GREEN}[OK] Kubectl est déjà installé. Étape ignorée.${NC}"
else
    echo -e "${BLUE}[ACTION] Installation de Kubectl...${NC}"
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
fi

# Configuration de l'alias 'k'
if grep -q "alias k='kubectl'" ~/.bashrc; then
    echo -e "${GREEN}[OK] L'alias 'k' est déjà configuré dans ~/.bashrc.${NC}"
else
    echo -e "${BLUE}[ACTION] Configuration de l'alias 'k' pour kubectl...${NC}"
    echo "alias k='kubectl'" >> ~/.bashrc
fi

# Création du Cluster K3d
if k3d cluster get iot-cluster &> /dev/null; then
    echo -e "${GREEN}[OK] Le cluster 'iot-cluster' existe déjà. Création ignorée.${NC}"
else
    echo -e "${BLUE}[ACTION] Création du cluster K3d 'iot-cluster'...${NC}"
    k3d cluster create iot-cluster \
      --api-port 6443 \
      -p "8080:80@loadbalancer" \
      -p "8888:8888@loadbalancer" \
      --agents 1
    
    echo -e "${YELLOW}[ATTENTE] Démarrage de l'API Kubernetes...${NC}"
    sleep 5
fi

# Création des Namespaces
if kubectl get namespace argocd &> /dev/null; then
    echo -e "${GREEN}[OK] Le namespace 'argocd' existe déjà.${NC}"
else
    echo -e "${BLUE}[ACTION] Création du namespace 'argocd'...${NC}"
    kubectl create namespace argocd
fi

if kubectl get namespace dev &> /dev/null; then
    echo -e "${GREEN}[OK] Le namespace 'dev' existe déjà.${NC}"
else
    echo -e "${BLUE}[ACTION] Création du namespace 'dev'...${NC}"
    kubectl create namespace dev
fi

# Configuration argo Cd
echo -e "\n${GREEN}[SUCCÈS] Script terminé !${NC}"
echo -e "${YELLOW}[IMPORTANT] Déconnectez-vous et reconnectez-vous, ou tapez 'su - \$USER' pour appliquer les droits Docker et l'alias 'k'.${NC}"

if kubectl get deployment argocd-server -n argocd &> /dev/null; then
    echo -e "${GREEN}[OK] Argo CD est déjà installé.${NC}"
else
    echo -e "${BLUE}[ACTION] Installation d'Argo CD...${NC}"
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    echo -e "${YELLOW}[ATTENTE] Démarrage des pods Argo CD (cela peut prendre 1 à 2 minutes)...${NC}"
    # Cette ligne met le script en pause jusqu'à ce que le serveur ArgoCD soit prêt
    kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s
fi
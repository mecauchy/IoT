.PHONY: all up start stop destroy clean status ssh logs provision reload deploy-apps deploy-ingress get-pods get-all help

# Variables
VM_NAME = mcauchyS

# Couleurs pour l'affichage
GREEN = \033[0;32m
YELLOW = \033[0;33m
RED = \033[0;31m
NC = \033[0m # No Color

## help: Affiche cette aide
help:
	@echo "$(GREEN)Makefile pour IoT Project - Part 2$(NC)"
	@echo ""
	@echo "$(YELLOW)Commandes disponibles:$(NC)"
	@echo "  $(GREEN)make up$(NC)              - Créer et démarrer la VM avec K3s"
	@echo "  $(GREEN)make start$(NC)           - Alias pour 'up'"
	@echo "  $(GREEN)make stop$(NC)            - Arrêter la VM"
	@echo "  $(GREEN)make destroy$(NC)         - Détruire complètement la VM"
	@echo "  $(GREEN)make clean$(NC)           - Alias pour 'destroy'"
	@echo "  $(GREEN)make status$(NC)          - Afficher le statut de la VM"
	@echo "  $(GREEN)make ssh$(NC)             - Se connecter à la VM en SSH"
	@echo "  $(GREEN)make provision$(NC)       - Re-provisionner la VM"
	@echo "  $(GREEN)make reload$(NC)          - Recharger la VM avec provisionnement"
	@echo "  $(GREEN)make logs$(NC)            - Afficher les logs de K3s"
	@echo ""
	@echo "$(YELLOW)Commandes Kubernetes:$(NC)"
	@echo "  $(GREEN)make get-pods$(NC)        - Lister tous les pods"
	@echo "  $(GREEN)make get-services$(NC)    - Lister tous les services"
	@echo "  $(GREEN)make get-ingress$(NC)     - Lister les ingress"
	@echo "  $(GREEN)make get-all$(NC)         - Lister toutes les ressources"
	@echo "  $(GREEN)make deploy-apps$(NC)     - Déployer les 3 applications"
	@echo "  $(GREEN)make deploy-ingress$(NC)  - Déployer l'ingress"
	@echo ""
	@echo "$(YELLOW)Autres:$(NC)"
	@echo "  $(GREEN)make all$(NC)             - Détruire et recréer complètement"
	@echo "  $(GREEN)make help$(NC)            - Afficher cette aide"

## all: Détruire et recréer la VM complètement
all: destroy up

## up: Créer et démarrer la VM
up:
	@echo "$(GREEN)Démarrage de la VM $(VM_NAME)...$(NC)"
	vagrant up

## start: Alias pour up
start: up

## stop: Arrêter la VM
stop:
	@echo "$(YELLOW)Arrêt de la VM $(VM_NAME)...$(NC)"
	vagrant halt

## destroy: Détruire la VM
destroy:
	@echo "$(RED)Destruction de la VM $(VM_NAME)...$(NC)"
	vagrant destroy -f

## clean: Alias pour destroy
clean: destroy

## status: Afficher le statut
status:
	@echo "$(GREEN)Statut de la VM:$(NC)"
	vagrant status

## ssh: Se connecter en SSH
ssh:
	vagrant ssh

## provision: Re-provisionner
provision:
	@echo "$(GREEN)Provisionnement de la VM...$(NC)"
	vagrant provision

## reload: Recharger la VM
reload:
	@echo "$(YELLOW)Rechargement de la VM...$(NC)"
	vagrant reload --provision

## logs: Afficher les logs K3s
logs:
	vagrant ssh -c "sudo journalctl -u k3s -f"

## get-pods: Lister les pods
get-pods:
	vagrant ssh -c "sudo k3s kubectl get pods"

## get-services: Lister les services
get-services:
	vagrant ssh -c "sudo k3s kubectl get services"

## get-ingress: Lister les ingress
get-ingress:
	vagrant ssh -c "sudo k3s kubectl get ingress"

## get-all: Lister toutes les ressources
get-all:
	vagrant ssh -c "sudo k3s kubectl get all,ingress"

## deploy-apps: Déployer les applications
deploy-apps:
	@echo "$(GREEN)Déploiement des applications...$(NC)"
	vagrant ssh -c "sudo k3s kubectl apply -f /vagrant/conf/app1/deployment.yml"
	vagrant ssh -c "sudo k3s kubectl apply -f /vagrant/conf/app2/deployment.yml"
	vagrant ssh -c "sudo k3s kubectl apply -f /vagrant/conf/app3/deployment.yml"

## deploy-ingress: Déployer l'ingress
deploy-ingress:
	@echo "$(GREEN)Déploiement de l'ingress...$(NC)"
	vagrant ssh -c "sudo k3s kubectl apply -f /vagrant/conf/ingress.yml"

## Default target
.DEFAULT_GOAL := help

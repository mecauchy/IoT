#!/bin/bash

set -e

echo "=========================================="
echo "Installation de K3s sur le serveur"
echo "=========================================="

# Installation de K3s en mode serveur
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--flannel-iface=eth1 --bind-address=${SERVER_IP} --advertise-address=${SERVER_IP}" sh -

echo "Attente du démarrage de K3s..."
sleep 30

# Vérifier que K3s est prêt
until sudo k3s kubectl get nodes | grep -q "Ready"; do
  echo "En attente que le nœud soit prêt..."
  sleep 5
done

echo "K3s est prêt !"

# Copier le fichier kubeconfig pour faciliter l'accès
mkdir -p /home/vagrant/.kube
sudo cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
sudo chown vagrant:vagrant /home/vagrant/.kube/config

# Configurer kubectl pour l'utilisateur vagrant
echo 'export KUBECONFIG=/home/vagrant/.kube/config' >> /home/vagrant/.bashrc
echo "alias k='kubectl'" >> /home/vagrant/.bashrc

echo "=========================================="
echo "Déploiement de l'application app1"
echo "=========================================="

# Appliquer le déploiement directement depuis le dossier synchronisé
sudo k3s kubectl apply -f /vagrant/conf/app1/deployment.yml

echo "=========================================="
echo "Déploiement de l'application app2"
echo "=========================================="

sudo k3s kubectl apply -f /vagrant/conf/app2/deployment.yml

echo "=========================================="
echo "Déploiement de l'application app3"
echo "=========================================="

sudo k3s kubectl apply -f /vagrant/conf/app3/deployment.yml

echo "=========================================="
echo "Déploiement de l'Ingress"
echo "=========================================="

sudo k3s kubectl apply -f /vagrant/conf/ingress.yml

# Attendre que les pods soient prêts
echo "Attente du démarrage des pods..."
sleep 10

# Vérifier le statut du déploiement
sudo k3s kubectl get deployments
sudo k3s kubectl get pods
sudo k3s kubectl get services
sudo k3s kubectl get ingress

echo "=========================================="
echo "Installation terminée !"
echo "=========================================="
echo "K3s est installé et les 3 applications sont déployées"
echo "Ingress configuré pour app1.com, app2.com et defaultBackend"
echo "Pour accéder à la VM : vagrant ssh ${HOSTNAME}"
echo "Pour vérifier les pods : kubectl get pods"
echo "=========================================="

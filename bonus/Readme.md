Architecture bonus — explication complète
Arborescence actuelle

bonus/
├── Vagrantfile                          ← Point d'entrée : définit les 2 VMs
├── scripts/
│   ├── gitlab/
│   │   └── provision.sh                 ← Provisionne VM2 (GitLab)
│   └── platform/
│       └── provision.sh                 ← Provisionne VM1 (k3s + Argo CD)
├── confs/
│   ├── namespaces/
│   │   ├── namespace-argocd.yaml        ← Namespace pour Argo CD
│   │   ├── namespace-dev.yaml           ← Namespace pour l'app
│   │   └── namespace-gitlab.yaml        ← Namespace réservé gitlab
│   ├── argocd/
│   │   ├── application.yaml             ← Définit quelle app Argo CD surveille
│   │   └── repo-secret.yaml             ← Dit à Argo CD où trouver le repo Git
│   ├── dev/
│   │   ├── deployment.yml               ← L'app à déployer (playground)
│   │   └── service.yml                  ← Expose l'app sur le port 30888
│   └── .gitlab-ci.yml                   ← Pipeline CI (validation des manifests)
└── scripts/
    └── install.sh                       ← Ancien script (k3d), plus utilisé


Qui fait quoi ?



# VM2 : gitlab-vm (192.168.56.10) — Le serveur Git

┌─────────────────────────────────────┐
│           gitlab-vm                 │
│                                     │
│  GitLab CE (apt install)            │
│  ├── /var/opt/gitlab  (données)     │
│  ├── /etc/gitlab      (config)      │
│  └── port 80 (HTTP)                 │
│                                     │
│  GitLab Runner (apt install)        │
│                                     │
│  Héberge le repo :                  │
│  root/iot-manifests                 │
│  └── confs/dev/                     │
│      ├── deployment.yml             │
│      └── service.yml                │
└─────────────────────────────────────┘

Son seul rôle : stocker ton code. C'est un serveur Git, rien d'autre. Tu te connectes à http://192.168.56.10, tu crées un projet, tu push tes manifests.



# VM1 : platform-vm (192.168.56.20) — Le cluster Kubernetes

┌─────────────────────────────────────┐
│          platform-vm                │
│                                     │
│  k3s (cluster Kubernetes)           │
│  ├── namespace: argocd              │
│  │   ├── Argo CD (pods)             │
│  │   ├── repo-secret.yaml           │
│  │   └── application.yaml           │
│  ├── namespace: dev                 │
│  │   ├── app-deployment (pod)       │
│  │   └── app-service (NodePort)     │
│  └── namespace: gitlab              │
│      └── (réservé, vide)            │
│                                     │
│  Accès :                            │
│  - Argo CD UI : port 30443          │
│  - App dev    : port 30888          │
└─────────────────────────────────────┘

Comment les fichiers communiquent entre eux ?

vagrant up
    │
    ├──→ Vagrantfile
    │       │
    │       ├──→ gitlab-vm : lance scripts/gitlab/provision.sh
    │       │       → installe GitLab CE
    │       │       → GitLab écoute sur http://192.168.56.10
    │       │
    │       └──→ platform-vm : lance scripts/platform/provision.sh
    │               │
    │               ├── 1. Installe k3s
    │               │
    │               ├── 2. kubectl apply confs/namespaces/*.yaml
    │               │       → crée argocd, dev, gitlab
    │               │
    │               ├── 3. Installe Argo CD dans namespace argocd
    │               │
    │               ├── 4. kubectl apply confs/argocd/repo-secret.yaml
    │               │       → dit à Argo CD : "le repo Git est à
    │               │         http://192.168.56.10/root/iot-manifests.git"
    │               │
    │               └── 5. kubectl apply confs/argocd/application.yaml
    │                       → dit à Argo CD : "surveille confs/dev/
    │                         dans ce repo, déploie dans namespace dev"
    │
    └──→ FIN : les 2 VMs sont up


Le flux GitOps en action (après le setup)

Toi (dev)                    GitLab (VM2)              Argo CD (VM1)           K8s cluster (VM1)
    │                            │                         │                        │
    │  git push (modif           │                         │                        │
    │  image: v2 dans            │                         │                        │
    │  deployment.yml)           │                         │                        │
    │ ──────────────────────────>│                         │                        │
    │                            │                         │                        │
    │                            │   poll toutes les 3min  │                        │
    │                            │ <───────────────────────│                        │
    │                            │                         │                        │
    │                            │   "voilà le contenu     │                        │
    │                            │    de confs/dev/"       │                        │
    │                            │ ───────────────────────>│                        │
    │                            │                         │                        │
    │                            │                         │  compare état actuel   │
    │                            │                         │  vs état désiré        │
    │                            │                         │                        │
    │                            │                         │  DIFF détecté !        │
    │                            │                         │  image v1 → v2         │
    │                            │                         │                        │
    │                            │                         │  kubectl apply         │
    │                            │                         │ ──────────────────────>│
    │                            │                         │                        │
    │                            │                         │                        │ pod recréé
    │                            │                         │                        │ avec image v2
    │                            │                         │                        │


# GitLab en local — comment ça fonctionne concrètement

C'est exactement la même chose que github.com ou gitlab.com, mais hébergé sur ta VM au lieu d'être sur Internet.

github.com          →  serveur Git chez Microsoft, accessible via Internet
gitlab.com          →  serveur Git chez GitLab Inc., accessible via Internet
192.168.56.10       →  serveur Git sur ta VM, accessible via ton réseau privé Vagrant

Quand on fais apt install gitlab-ce, ça installe sur ta VM :

- Un serveur Nginx (serveur web → l'interface UI)
- Un serveur Git (stocke les repos)
- PostgreSQL (base de données utilisateurs, projets, issues…)
- Redis (cache, files d'attente)
- Puma (application Ruby on Rails = la logique GitLab)
- Gitaly (accès aux fichiers Git sur le disque)

Tout ça tourne comme des services système (comme Apache ou MySQL), pas dans des conteneurs.

2. Pourquoi une adresse IP ?

GitLab a besoin d'une external_url pour savoir comment les utilisateurs accèdent à lui. Cette URL est utilisée partout :

┌─────────────────────────────────────────────────────────┐
│  external_url = "http://192.168.56.10"                  │
│                                                         │
│  Interface web :  http://192.168.56.10                  │
│  Clone HTTP :     http://192.168.56.10/root/projet.git  │
│  API REST :       http://192.168.56.10/api/v4/...       │
│  Liens dans les emails, merge requests, etc.            │
└─────────────────────────────────────────────────────────┘

L'IP 192.168.56.10 vient du Vagrantfile :

gitlab.vm.network "private_network", ip: "192.168.56.10"

C'est un réseau privé entre ta machine hôte et les VMs. Seul toi y as accès.

3. Est-ce que je peux tout faire via l'interface web ?

Oui, absolument. Après vagrant up, tu ouvres ton navigateur :

Étape 1 — Se connecter

URL      : http://192.168.56.10
Login    : root
Password : (celui dans /home/vagrant/gitlab_root_password.txt)

Pour le récupérer depuis ton terminal :

vagrant ssh gitlab-vm -c "cat /home/vagrant/gitlab_root_password.txt"

Étape 2 — Créer le projet (via UI)


Menu "+" → New project → Create blank project
  Project name : iot-manifests
  Visibility   : Public (pour qu'Argo CD puisse cloner sans token)
  Initialize with README : oui
→ Create project

Etape 3 : Pousser les manifest

Depuis ton terminal (git push classique)

4. Structure du repo GitLab attendue


Argo CD est configuré pour lire path: confs/dev dans le repo. Donc le repo sur GitLab doit ressembler à ça :


root/iot-manifests (sur GitLab)├── confs/│   
									└── dev/│
									       ├── deployment.ymlyml    ← Argo CD lit ça│
									       └── service.yml       ← Argo CD lit ça
								├── .gitlab-ci.yml            ← GitLab Runner lit ça(optionnel)
								└── README.md


5. Flux complet illustre

TOI (navigateur ou terminal)
  │
  │  1. Ouvre http://192.168.56.10
  │  2. Crée le projet root/iot-manifests
  │  3. Push confs/dev/deployment.yml + service.yml
  │
  ▼
GITLAB (VM2 - 192.168.56.10)
  │
  │  Stocke les fichiers dans /var/opt/gitlab/git-data/
  │  Accessible via HTTP sur le port 80
  │
  ▼
ARGO CD (VM1 - 192.168.56.20)
  │
  │  Connaît le repo grâce à repo-secret.yaml
  │  Sait quoi surveiller grâce à application.yaml
  │  Poll le repo toutes les ~3 minutes
  │
  │  "Est-ce que confs/dev/ a changé ?"
  │     │
  │     ├── NON → ne fait rien
  │     └── OUI → kubectl apply les nouveaux manifests
  │
  ▼
KUBERNETES (VM1 - namespace dev)
  │
  │  Crée/met à jour le pod avec la nouvelle image
  │  Expose sur NodePort 30888
  │
  ▼
TOI (navigateur)
  │
  │  http://192.168.56.20:30888 → l'app mise à jour
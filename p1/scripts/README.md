# IoT

┌─────────────────────────────────────────────────┐
│           Machine (Hôte)                      │
│                                                 │
│  ┌──────────────────────────────────────────┐  │
│  │  Dossier: ./shared/                      │  │
│  │  Contient: token (généré par serveur)    │  │
│  └──────────────────────────────────────────┘  │
│               ↕ Synchronisation ↕               │
│  ┌─────────────────┐    ┌──────────────────┐   │
│  │ VM: mcauchyS    │    │ VM: mcauchySW    │   │
│  │ IP: .110        │←──→│ IP: .111         │   │
│  │ Rôle: Serveur   │    │ Rôle: Worker     │   │
│  │ RAM: 1GB        │    │ RAM: 1GB         │   │
│  │                 │    │                  │   │
│  │ /vagrant_shared │    │ /vagrant_shared  │   │
│  │ (même dossier)  │    │ (même dossier)   │   │
│  └─────────────────┘    └──────────────────┘   │
└─────────────────────────────────────────────────┘

- 2 VMs qui communiquent sur le réseau 192.168.56.0/24
- Un cluster K3s fonctionnel avec 1 serveur + 1 worker
- Token partagé de manière sécurisée via le dossier synchronisé
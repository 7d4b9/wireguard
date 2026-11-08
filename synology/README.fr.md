# WireGuard — Synology ARMv7

Compilation et déploiement de WireGuard en espace utilisateur pour les NAS Synology ARMv7 du lab Vegito.

Le dépôt produit deux exécutables :

- **`wireguard-go`** : démon WireGuard en espace utilisateur, utilisant `/dev/net/tun`.
- **`wg`** : utilitaire de configuration des interfaces, des clés et des pairs.

Le but est de raccorder les NAS au backbone WireGuard existant (`10.6.6.0/24`) sans modifier leur passerelle par défaut ni perturber les services DSM, NFS et SFTPGo.

## 1. Architecture réseau

```text
                        Beryl (serveur WireGuard)
                               10.6.6.1
                                  │
               ┌──────────────────┼──────────────────┐
               │                  │                  │
        PC Debian             MacBook          Pont NFS
        10.6.6.2              10.6.6.3         10.6.6.4
               │
               └───────────── Backbone ───────────────┐
                                                      │
                                     ┌────────────────┴─────────────┐
                                     │                              │
                                NAS Vanves                      NAS PDC
                                10.6.6.5                        10.6.6.6
```

| Équipement | Adresse WireGuard | Rôle |
| --- | --- | --- |
| Beryl | `10.6.6.1` | Serveur WireGuard |
| PC Debian | `10.6.6.2` | Lab / Vault |
| MacBook | `10.6.6.3` | Poste de développement |
| Pont NFS | `10.6.6.4` | Pont réseau |
| NAS Vanves | `10.6.6.5` | Client Synology ARMv7 |
| NAS PDC | `10.6.6.6` | Client Synology ARMv7 |

Les adresses `.5` et `.6` sont des attributions prévues : vérifier qu'elles sont libres avant de créer les pairs sur le Beryl.

## 2. Arborescence du dépôt

```text
wireguard/
├── Makefile
├── README.md
├── synology/
│   ├── synology.mk
│   ├── start.sh
│   └── dist/
│       └── linux-armv7/
│           ├── wg
│           └── wireguard-go
├── wireguard-go/
└── wireguard-tools/
```

Les répertoires `wireguard-go/` et `wireguard-tools/` contiennent les sources amont. Il est recommandé de les suivre comme sous-modules Git à des révisions déterminées, si ce n'est pas déjà le cas.

## 3. Prérequis

### Machine de compilation

- Docker Engine et Docker CLI.
- Prise en charge de `linux/arm/v7` (émulation binfmt/QEMU ou hôte ARMv7).
- Prise en charge de `linux/amd64` pour le conteneur Go.
- GNU Make et Git.

Vérifier l'exécution ARMv7 :

```sh
docker run --rm --platform linux/arm/v7 alpine:3.22 uname -m
```

### NAS Synology

- CPU ARMv7.
- Accès root.
- Interface TUN disponible (`/dev/net/tun`).
- Commande `ip` fonctionnelle.

Tester TUN sans toucher aux interfaces existantes :

```sh
ls -l /dev/net/tun
ip tuntap add dev wg-test mode tun
ip link show wg-test
ip link delete wg-test
```

## 4. Compilation

Depuis la racine du dépôt :

```sh
make build
```

Cible principale du `Makefile` :

```makefile
WG_SYNOLOGY_DIR ?= $(CURDIR)/synology
include $(WG_SYNOLOGY_DIR)/synology.mk

build: build-synology
clean: clean-synology
```

### Compiler `wg`

```sh
make build-wg-synology
```

La compilation s'effectue dans `alpine:3.22` en `linux/arm/v7`, avec GCC et musl. Le lien statique est demandé via `LDFLAGS=-static`.

### Compiler `wireguard-go`

```sh
make build-wireguard-go-synology
```

La compilation Go est croisée depuis le conteneur AMD64 :

```sh
CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 go build -trimpath -o /dist/wireguard-go .
```

### Artefacts

```text
synology/dist/linux-armv7/wg
synology/dist/linux-armv7/wireguard-go
```

Vérifications :

```sh
file synology/dist/linux-armv7/*
readelf -l synology/dist/linux-armv7/wg | grep INTERP || true
```

Le binaire `wg` doit être de type ELF ARM 32 bits et ne pas nécessiter d'interpréteur ELF dynamique.

Nettoyage :

```sh
make clean
```

**Note :** cette cible supprime `synology/dist/linux-armv7/`, mais pas nécessairement les fichiers objets générés dans `wireguard-tools/src/`.

## 5. Installation sur Synology

Séparer l'installation du service et les données persistantes :

```text
/volume1/services/wireguard/
├── bin/
│   ├── wg
│   └── wireguard-go
├── config/
│   ├── wg.conf
│   ├── network.env
│   ├── private.key
│   └── public.key
└── scripts/
    └── start.sh
```

`/volume1/lab-data/` reste réservé aux données persistantes des services, par exemple `/volume1/lab-data/vault/raft/`. Les binaires et scripts WireGuard n'ont pas besoin d'y être placés.

Créer les répertoires sur le NAS :

```sh
mkdir -p /volume1/services/wireguard/{bin,config,scripts}
chmod 700 /volume1/services/wireguard/config
```

Si le shell Synology ne prend pas en charge l'expansion `{...}`, utiliser :

```sh
mkdir -p /volume1/services/wireguard/bin \
         /volume1/services/wireguard/config \
         /volume1/services/wireguard/scripts
```

Copier les fichiers depuis le PC (adapter l'utilisateur et le nom d'hôte) :

```sh
scp synology/dist/linux-armv7/wg \
    synology/dist/linux-armv7/wireguard-go \
    david@nas.vanves:/volume1/services/wireguard/bin/

scp synology/start.sh \
    david@nas.vanves:/volume1/services/wireguard/scripts/start.sh
```

Si le compte SSH n'a pas les droits d'écriture, copier d'abord dans son répertoire personnel puis déplacer les fichiers en tant que root.

Sur le NAS :

```sh
chmod 755 /volume1/services/wireguard/bin/wg
chmod 755 /volume1/services/wireguard/bin/wireguard-go
chmod 755 /volume1/services/wireguard/scripts/start.sh

/volume1/services/wireguard/bin/wg --version
/volume1/services/wireguard/bin/wireguard-go --version
```

## 6. Clés WireGuard

Chaque NAS possède sa propre paire de clés. Sur chaque NAS :

```sh
cd /volume1/services/wireguard/config
../bin/wg genkey > private.key
chmod 600 private.key
../bin/wg pubkey < private.key > public.key
cat public.key
```

Transmettre **uniquement la clé publique** au Beryl. Ne jamais versionner `private.key`, ni `wg.conf` s'il contient une clé privée.

## 7. Configuration des NAS

Le script `synology/start.sh` charge :

```text
/volume1/services/wireguard/config/network.env
/volume1/services/wireguard/config/wg.conf
```

### NAS Vanves

`network.env` :

```sh
WG_ADDRESS=10.6.6.5/32
WG_NETWORK=10.6.6.0/24
```

`wg.conf` :

```ini
[Interface]
PrivateKey = <CLE_PRIVEE_NAS_VANVES>

[Peer]
PublicKey = <CLE_PUBLIQUE_BERYL>
Endpoint = 192.168.50.11:51820
AllowedIPs = 10.6.6.0/24
PersistentKeepalive = 25
```

### NAS PDC

`network.env` :

```sh
WG_ADDRESS=10.6.6.6/32
WG_NETWORK=10.6.6.0/24
```

`wg.conf` :

```ini
[Interface]
PrivateKey = <CLE_PRIVEE_NAS_PDC>

[Peer]
PublicKey = <CLE_PUBLIQUE_BERYL>
Endpoint = <ENDPOINT_PUBLIC_BERYL>:51820
AllowedIPs = 10.6.6.0/24
PersistentKeepalive = 25
```

Le port UDP `51820` doit être accessible depuis le site PDC, avec la redirection NAT nécessaire vers le Beryl.

**Important :** `wg setconf` n'accepte pas les champs `Address`, `DNS` ou `PostUp` de `wg-quick`. Les adresses et routes sont configurées séparément par `ip`.

Protéger les fichiers :

```sh
chmod 600 /volume1/services/wireguard/config/private.key
chmod 600 /volume1/services/wireguard/config/wg.conf
chmod 600 /volume1/services/wireguard/config/network.env
```

`network.env` est exécuté comme du code shell par le script de démarrage : ne le rendre modifiable que par des administrateurs de confiance.

### Configuration côté Beryl

Ajouter un pair par NAS, en conservant les pairs existants :

```ini
# NAS Vanves
[Peer]
PublicKey = <CLE_PUBLIQUE_NAS_VANVES>
AllowedIPs = 10.6.6.5/32

# NAS PDC
[Peer]
PublicKey = <CLE_PUBLIQUE_NAS_PDC>
AllowedIPs = 10.6.6.6/32
```

Les deux blocs sont illustratifs : les intégrer via le mécanisme de configuration des pairs du serveur WireGuard Beryl, sans écraser sa configuration actuelle.

Vérifier que le pare-feu Beryl autorise le transfert entre pairs WireGuard lorsque nécessaire.

## 8. Démarrage

Le script actuellement présent dans `synology/start.sh` :

1. Charge `network.env`.
2. Démarre `wireguard-go` si l'interface `wg-vault` n'existe pas.
3. Applique `wg.conf` avec `wg setconf`.
4. Configure l'adresse IP et la route `10.6.6.0/24`.
5. Active l'interface et affiche l'état WireGuard.

Lancer en root :

```sh
/volume1/services/wireguard/scripts/start.sh
```

Le script utilise :

```sh
WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1
```

Cette variable force le moteur userspace lorsque `wireguard-go` considère que le noyau dispose d'une implémentation WireGuard.

**Compatibilité DSM :** la commande `ip addr replace` utilisée dans la version actuelle de `start.sh` peut être absente de certaines versions de `ip`. Vérifier sa prise en charge ; à défaut, utiliser `ip addr show` puis `ip addr add` seulement si l'adresse manque. Après le démarrage du démon, il peut aussi être nécessaire d'attendre brièvement la création de son socket de contrôle avant `wg setconf`.

## 9. Vérifications réseau

```sh
ip link show wg-vault
ip -4 addr show wg-vault
ip route get 10.6.6.2
/volume1/services/wireguard/bin/wg show wg-vault
```

Vérifier le dernier handshake et les compteurs de transfert :

```sh
/volume1/services/wireguard/bin/wg show
```

Tester les communications :

```sh
ping 10.6.6.1
ping 10.6.6.2
```

Un handshake réussi confirme le tunnel avec le Beryl, mais **ne garantit pas** que le transfert entre pairs soit autorisé par son pare-feu.

### Routage attendu sur le NAS Vanves

```text
192.168.50.0/24  -> interface LAN
10.6.6.0/24      -> wg-vault
0.0.0.0/0        -> passerelle LAN 192.168.50.1
```

Ne pas utiliser `AllowedIPs = 0.0.0.0/0` : cela créerait un tunnel complet non souhaité et risquerait de perturber les autres services du NAS.

## 10. Démarrage automatique sous DSM

Dans **Panneau de configuration → Planificateur de tâches** :

1. Créer une **tâche déclenchée** au démarrage.
2. Choisir **Script défini par l'utilisateur**.
3. Exécuter en tant que **root**.
4. Indiquer :

```sh
/volume1/services/wireguard/scripts/start.sh
```

Le volume `/volume1` et le réseau doivent être disponibles avant l'exécution. Prévoir une temporisation ou une logique de retry si nécessaire.

Une tâche de démarrage DSM ne supervise pas le démon après son lancement : pour une meilleure résilience, ajouter ultérieurement `stop.sh`, `restart.sh`, `status.sh` et une supervision du processus.

## 11. Intégration avec Vault Raft

Le réseau WireGuard doit permettre les échanges privés entre les trois nœuds Vault :

| Nœud | IP WireGuard | Ports |
| --- | --- | --- |
| PC Debian | `10.6.6.2` | TCP `8200`, `8201` |
| NAS Vanves | `10.6.6.5` | TCP `8200`, `8201` |
| NAS PDC | `10.6.6.6` | TCP `8200`, `8201` |

- `8200` : API Vault.
- `8201` : communications internes du cluster Vault.

Chaque nœud doit annoncer une adresse de cluster accessible depuis les autres nœuds, et disposer de son **propre stockage Raft local**. Le répertoire Raft ne doit pas être placé sur un partage NFS distant.

Ordre de démarrage souhaité :

```text
Démarrage DSM
    ↓
Montage de /volume1 et initialisation réseau
    ↓
Démarrage WireGuard
    ↓
Démarrage Vault
    ↓
Reconnexion / participation au cluster Raft
```

Ne pas bloquer indéfiniment le démarrage de Vault sur la disponibilité du leader : les nœuds doivent pouvoir participer aux élections Raft après une panne.

**Ne pas initialiser indépendamment les NAS** : ils doivent rejoindre le cluster Vault existant, en conservant une configuration d'auto-unseal compatible.

## 12. Sécurité et exploitation

- Garder les clés privées hors du dépôt Git.
- Restreindre les permissions du dossier `config/`.
- Ne publier sur Internet que le port UDP WireGuard requis.
- Ne pas exposer publiquement le port Vault Raft `8201`.
- Vérifier les règles de transfert entre pairs sur le Beryl.
- Préserver la route par défaut de chaque NAS.
- Vérifier les versions de Vault avant tout mélange de nœuds au sein du même cluster.
- Le Beryl constitue un point de défaillance commun pour ce backbone.

`.gitignore` conseillé :

```gitignore
synology/dist/
*.key
*.private
wg.conf
network.env
*.log
*.tmp
```

## 13. Dépannage

### Aucun handshake

```sh
/volume1/services/wireguard/bin/wg show
```

Vérifier la clé publique du serveur, les clés des NAS, l'endpoint, UDP `51820`, la redirection NAT et les `AllowedIPs`.

### Handshake OK, mais ping impossible

```sh
ip route get 10.6.6.2
/volume1/services/wireguard/bin/wg show wg-vault
```

Vérifier le transfert entre pairs sur le Beryl et le pare-feu de la destination.

### Interface impossible à créer

```sh
ls -l /dev/net/tun
ip link show wg-vault
/volume1/services/wireguard/bin/wireguard-go --version
```

### Perte d'accès aux services du NAS

```sh
ip route
```

Vérifier que la route par défaut pointe toujours vers le routeur LAN.

## 14. État du projet

| Élément | État |
| --- | --- |
| Compilation ARMv7 de `wireguard-go` | Validée |
| Compilation statique ARMv7 de `wg` | Validée |
| Exécution de `wg` sur Synology | Validée |
| Support TUN Synology | Validé |
| Makefile et `synology.mk` | Présents |
| `synology/start.sh` | Présent, à tester en conditions réelles |
| Pair NAS Vanves sur Beryl | À configurer |
| Pair NAS PDC sur Beryl | À configurer |
| Démarrage automatique DSM | À configurer |
| Intégration Vault Raft | À venir |

## 15. Références

- WireGuard : https://www.wireguard.com/
- Sources `wireguard-go` : https://github.com/WireGuard/wireguard-go
- Sources `wireguard-tools` : https://git.zx2c4.com/wireguard-tools/
- Synology DSM : https://www.synology.com/

## Licence

Les composants amont conservent leurs licences respectives (`LICENSE` et `COPYING` dans les dépôts sources). Définir séparément la licence applicable aux scripts et aux fichiers de build propres à ce dépôt.

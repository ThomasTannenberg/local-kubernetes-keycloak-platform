# Local Kubernetes Keycloak Platform

Dieses Repository enthält ein reproduzierbares lokales Kubernetes Setup für die Bewerberaufgabe.

Ziel ist ein lokales K3s Multi Node Cluster mit Keycloak, PostgreSQL, Ingress, TLS, persistentem Storage und GitOps Deployment.

## Komponenten

Verwendete Hauptkomponenten:

```text
K3s
KVM/libvirt
HAProxy
Ansible
Fleet
Helm
cert-manager
Sealed Secrets
Longhorn
PostgreSQL
Traefik
Keycloak
```

## Architektur

Das Setup besteht aus sieben lokalen VMs.

```text
k3s-lb-1       192.168.122.10   HAProxy LoadBalancer

k3s-server-1   192.168.122.11   Control Plane
k3s-server-2   192.168.122.12   Control Plane
k3s-server-3   192.168.122.13   Control Plane

k3s-agent-1    192.168.122.21   Worker
k3s-agent-2    192.168.122.22   Worker
k3s-agent-3    192.168.122.23   Worker
```

HAProxy ist der zentrale Einstiegspunkt.

```text
Kubernetes API:
192.168.122.10:6443 -> K3s Server Nodes

HTTP:
192.168.122.10:80 -> Traefik NodePort 30080

HTTPS:
192.168.122.10:443 -> Traefik NodePort 30443
```

Keycloak ist über Traefik Ingress erreichbar.

```text
https://keycloak.local.example
```

Dafür muss auf dem Host folgender Eintrag gesetzt werden:

```text
192.168.122.10 keycloak.local.example
```

## Voraussetzungen

Benötigte Tools auf dem Host:

```bash
ansible
kubectl
helm
virsh
virt-install
make
kubeseal
git
ssh
curl
qemu-img
cloud-localds
```

Zusätzlich wird benötigt:

```text
Linux Host
KVM/libvirt
aktivierte CPU Virtualisierung
libvirt default network
ausreichend RAM und CPU
```

## Installation

Das komplette Setup wird über das Makefile gestartet.

```bash
make install
```

Dieser Befehl führt intern aus:

```text
make vm-create
make cluster-create
make fleet-bootstrap
```

Danach übernimmt Fleet die Installation der Plattform Komponenten aus dem Repository.

## Einzelne Schritte

VMs erstellen:

```bash
make vm-create
```

K3s Cluster erstellen:

```bash
make cluster-create
```

Fleet installieren und Repository verbinden:

```bash
make fleet-bootstrap
```

Status prüfen:

```bash
make validate
make fleet-status
```

Cleanup:

```bash
make cleanup
```

## Zugriff auf das Cluster

Nach der Installation liegt die Kubeconfig hier:

```text
cluster/ansible/k3s.yaml
```

Die Datei wird nicht ins Git Repository übernommen.

Kubeconfig setzen:

```bash
export KUBECONFIG=cluster/ansible/k3s.yaml
```

Cluster prüfen:

```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A
```

## Zugriff auf Keycloak

URL:

```text
https://keycloak.local.example
```

Admin Benutzer:

```text
admin
```

Admin Passwort auslesen:

```bash
kubectl get secret keycloak-admin -n keycloak \
  -o jsonpath="{.data.admin-password}" | base64 -d; echo
```

HTTPS prüfen:

```bash
curl -vk https://keycloak.local.example
```

Da dieses lokale Setup ein selbstsigniertes Zertifikat verwendet, zeigt der Browser eine Zertifikatswarnung. Das ist in diesem Setup erwartet.

## Validierung

Das Makefile enthält ein Validierungsziel.

```bash
make validate
```

Dabei werden unter anderem geprüft:

```text
Nodes
Pods
Fleet Status
Helm Releases
Zertifikate
StorageClasses
PVCs
PVs
Services
Ingress Ressourcen
Keycloak HTTPS Zugriff
```

Wichtige Einzelbefehle:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get gitrepo,bundles,bundledeployments -A
helm list -A
kubectl get certificate -A
kubectl get storageclass
kubectl get pvc -A
kubectl get ingress -A
curl -vk https://keycloak.local.example
```

## Repository Struktur

```text
.
├── Makefile
├── README.md
├── cluster/
│   ├── libvirt/
│   └── ansible/
├── docs/
│   └── Fragen_beantworten.md
├── fleet/
│   └── gitrepo.yaml
└── platform/
    ├── cert-manager/
    ├── cert-manager-issuer/
    ├── keycloak/
    ├── longhorn/
    ├── postgresql/
    ├── sealed-secrets/
    ├── secrets/
    └── traefik/
```

Nicht versionierte lokale Dateien:

```text
.local-secrets/
tmp/
cluster/ansible/k3s.yaml
cluster/ansible/.k3s-bootstrap-token
```

Diese Dateien dürfen nicht ins Git Repository übernommen werden.

## Secrets

Sensible Werte werden nicht im Klartext im Repository gespeichert.

Verwendet wird Sealed Secrets.

Betroffene Secrets:

```text
Keycloak Admin Passwort
Keycloak Datenbank Passwort
PostgreSQL Admin Passwort
```

Die verschlüsselten SealedSecret Dateien liegen unter:

```text
platform/secrets/
```

Der Sealed Secrets Controller läuft im Namespace:

```text
kube-system
```

Wichtig:

Ein SealedSecret ist an den öffentlichen Schlüssel eines bestimmten Sealed Secrets Controllers gebunden. Wenn das Cluster neu erstellt wird und der alte private Schlüssel nicht wiederhergestellt wird, können vorhandene SealedSecret Dateien nicht mehr entschlüsselt werden.

Der private Schlüssel des Sealed Secrets Controllers muss daher lokal gesichert werden.

```bash
mkdir -p .local-secrets

kubectl -n kube-system get secret \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > .local-secrets/sealed-secrets-key-backup.yaml

chmod 600 .local-secrets/sealed-secrets-key-backup.yaml
```

Diese Datei darf nicht ins Git Repository.

## TLS und Let’s Encrypt

In diesem lokalen Setup wird kein echtes Let’s Encrypt Zertifikat verwendet.

Grund:

```text
keycloak.local.example ist nur lokal über /etc/hosts erreichbar.
Let’s Encrypt kann diese Domain nicht öffentlich validieren.
Es gibt keine DNS Challenge mit echtem DNS Provider.
```

Deshalb wird lokal ein selfsigned ClusterIssuer über cert-manager verwendet.

In einer produktionsnahen Umgebung würde Let’s Encrypt über DNS-01 oder HTTP-01 mit echter Domain verwendet werden.

## Wichtige Hinweise

Das Setup ist bewusst umfangreicher als ein einfaches Single Node Lab.

Es nutzt:

```text
mehrere Control Plane Nodes
mehrere Worker Nodes
HAProxy als Einstiegspunkt
Traefik als Ingress Controller
Longhorn für persistenten Storage
PostgreSQL als separate Datenbank
Fleet für GitOps
Sealed Secrets für sensible Werte
```

Für kleinere lokale Tests wäre ein Single Node Setup mit kind oder minikube einfacher.

## Weiterführende Dokumentation

Die ausführliche Beantwortung der Bewerberaufgabe liegt unter:

```text
docs/Fragen_beantworten.md
```

Dort sind Architekturentscheidungen, Einschränkungen, Validierung und Troubleshooting ausführlicher beschrieben.
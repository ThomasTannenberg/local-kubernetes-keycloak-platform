# Local Kubernetes Keycloak Platform

Dieses Repository enthält ein lokales Kubernetes Setup für die Bewerberaufgabe.

Ziel ist ein reproduzierbares lokales Kubernetes Cluster mit Keycloak, PostgreSQL, Ingress und TLS.


## Inhalt

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

Das lokale Cluster besteht aus sieben VMs.

```text
k3s-lb-1       192.168.122.10   HAProxy LoadBalancer

k3s-server-1   192.168.122.11   Control Plane 
k3s-server-2   192.168.122.12   Control Plane 
k3s-server-3   192.168.122.13   Control Plane 

k3s-agent-1    192.168.122.21   Worker
k3s-agent-2    192.168.122.22   Worker
k3s-agent-3    192.168.122.23   Worker
```

HAProxy übernimmt zwei Aufgaben:

```text
Kubernetes API:
192.168.122.10:6443 -> K3s Server Nodes

HTTP und HTTPS:
192.168.122.10:80  -> Traefik NodePort 30080
192.168.122.10:443 -> Traefik NodePort 30443
```

Keycloak ist über Traefik Ingress erreichbar.

```text
https://keycloak.local.example
```

Dafür ist auf dem Host folgender Eintrag notwendig:

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

Zusätzlich muss KVM/libvirt auf dem Host funktionieren.

## Installation

Das komplette Setup kann über das Makefile gestartet werden.

```bash
make install
```

Das führt intern diese Schritte aus:

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

Admin User:

```text
admin
```

Admin Passwort auslesen:

```bash
kubectl get secret keycloak-admin -n keycloak \
  -o jsonpath="{.data.admin-password}" | base64 -d; echo
```

HTTPS testen:

```bash
curl -vk https://keycloak.local.example
```

Da lokal ein selbstsigniertes Zertifikat verwendet wird, zeigt der Browser wahrscheinlich eine Zertifikatswarnung. Das ist in diesem Setup erwartet.

## Validierung

Cluster:

```bash
kubectl get nodes -o wide
kubectl get namespaces
kubectl get pods -A -o wide
```

Fleet:

```bash
kubectl get gitrepo -A
kubectl get bundles -n fleet-local
kubectl get bundledeployments -A
```

Helm Releases:

```bash
helm list -A
```

Storage:

```bash
kubectl get storageclass
kubectl get pvc -A
kubectl get pv
```

cert-manager:

```bash
kubectl get pods -n cert-manager
kubectl get crds | grep cert-manager
kubectl get clusterissuer
kubectl get certificate -A
```

Traefik:

```bash
kubectl get pods -n traefik
kubectl get svc -n traefik
kubectl get ingressclass
```

Keycloak:

```bash
kubectl get pods -n keycloak
kubectl get svc -n keycloak
kubectl get ingress -n keycloak
kubectl get certificate -n keycloak
kubectl logs keycloak-0 -n keycloak
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

## Wichtige Hinweise

### Sealed Secrets

Ich verwende Sealed Secrets, damit sensible Werte nicht im Klartext im Git Repository liegen.

Das betrifft vor allem:

```text
Keycloak Admin Passwort
Keycloak Datenbank Passwort
PostgreSQL Admin Passwort
```

Wichtig ist dabei der Ablauf beim ersten Benutzen.

Die Sealed Secrets Dateien werden nicht automatisch beim ersten Start aus dem Nichts erzeugt. Sie müssen einmal manuell erstellt, mit `kubeseal` verschlüsselt und danach an der richtigen Stelle im Repository abgelegt werden.

```text
platform/secrets/
```

Aktuelle Dateien:

```text
keycloak-admin.sealedsecret.yaml
keycloak-database.sealedsecret.yaml
keycloak-postgresql-auth.sealedsecret.yaml
```

Der grobe Ablauf beim ersten Erstellen ist:

```text
1. Normale Kubernetes Secrets lokal mit kubectl erzeugen
2. Diese Secrets nicht direkt ins Git legen
3. Die Secrets mit kubeseal gegen den Sealed Secrets Controller verschlüsseln
4. Die erzeugten SealedSecret Dateien unter platform/secrets ablegen
5. Die temporären Klartext Secret Dateien wieder löschen
6. Änderungen committen und pushen
7. Fleet synchronisiert die SealedSecret Dateien ins Cluster
8. Der Sealed Secrets Controller erzeugt daraus die echten Kubernetes Secrets
```

Beispiel Keycloak Admin Secret:

```bash
kubectl -n keycloak create secret generic keycloak-admin \
  --from-literal=admin-password='KEYCLOAK_ADMIN_PASSWORT' \
  --dry-run=client -o yaml > /tmp/keycloak-admin.secret.yaml
```

Danach versiegeln:

```bash
kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  --format yaml \
  < /tmp/keycloak-admin.secret.yaml \
  > platform/secrets/keycloak-admin.sealedsecret.yaml
```

Danach die Klartext Datei löschen:

```bash
rm /tmp/keycloak-admin.secret.yaml
```

Das gleiche Prinzip gilt für die PostgreSQL und Keycloak Datenbank Secrets.

Wichtig ist außerdem, dass der private Key des Sealed Secrets Controllers gesichert wird.

Ein SealedSecret ist an den öffentlichen Schlüssel eines bestimmten Sealed Secrets Controllers gebunden. Der passende private Schlüssel liegt im Cluster. Wenn das Cluster neu gebaut wird und dieser private Schlüssel nicht wiederhergestellt wird, können die vorhandenen SealedSecret Dateien nicht mehr entschlüsselt werden.

Typischer Fehler:

```text
no key could decrypt secret
```

Deshalb sichere ich den Sealed Secrets Key lokal:

```bash
mkdir -p .local-secrets

kubectl -n kube-system get secret \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > .local-secrets/sealed-secrets-key-backup.yaml

chmod 600 .local-secrets/sealed-secrets-key-backup.yaml
```

Diese Datei darf nicht ins Git Repository.

Wiederherstellen:

```bash
kubectl apply -f .local-secrets/sealed-secrets-key-backup.yaml
kubectl -n kube-system rollout restart deployment sealed-secrets-controller
```
Wenn kein Key Backup vorhanden ist, müssen die Secrets neu erstellt und erneut mit dem neuen Controller verschlüsselt werden.
Dabei kommt es aber zu Problemen mit Fleet da die sealed Secrets als modified gelten.

Am besten die secrets neu erzeugen und ein backup des sealed-secrets-keys anlegen. 
```

## TLS und Let’s Encrypt

In diesem lokalen Setup wird kein echtes Let’s Encrypt Zertifikat verwendet.

Grund:

```text
keycloak.local.example ist nur lokal über /etc/hosts erreichbar.
Let’s Encrypt kann diese Domain nicht öffentlich validieren.
Es gibt keine DNS Challenge mit echtem DNS Provider.
```

Deshalb wird lokal ein selfsigned ClusterIssuer über cert-manager genutzt.

Für eine produktionsnahe Umgebung würde ich Let’s Encrypt über DNS-01 oder HTTP-01 mit echter Domain verwenden.

## Weitere Dokumentation

Die ausführliche Beantwortung der Bewerberaufgabe liegt unter:

```text
docs/Fragen_beantworten.md
```

Dort sind die Entscheidungen, Einschränkungen, Validierung und Troubleshooting ausführlicher beschrieben.

## Cleanup

Das gesamte Setup kann wieder entfernt werden mit:

```bash
make cleanup
```

Dabei werden das K3s Cluster und die VMs entfernt.

Das Ubuntu Cloud Image bleibt standardmäßig erhalten. Wenn es ebenfalls gelöscht werden soll, kann das Cleanup Skript mit `REMOVE_BASE_IMAGE=1` gestartet werden.
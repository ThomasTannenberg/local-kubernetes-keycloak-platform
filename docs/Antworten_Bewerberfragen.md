# Antworten zur Bewerberaufgabe

Dieses Dokument beschreibt mein lokales Kubernetes Setup für die Bewerberaufgabe.

# 1. Lokales Kubernetes Cluster
## 1.1 Wahl der Kubernetes Distribution

Ich habe mich für K3s entschieden.

In der Vergangenheit habe ich private Setups zum Lernen und Testen mit minikube aufgebaut. Minikube hätte die Anforderungen der Aufgabeebenfalls erfüllt.
Für diese Aufgabe wollte ich aber ein Setup erstellen, welches näher an einer produktionsnahen Kubernetes Umgebung liegt. 
Deshalb verwende ich K3s auf mehreren lokalen virtuellen Maschinen.

Verwendete Versionen und Grundkomponenten:


Kubernetes Distribution: K3s
Kubernetes Version: v1.35.4+k3s1
Host OS: Ubuntu 26.04 LTS
VM OS: Ubuntu 22.04.5 LTS
Container Runtime: containerd://2.2.3-k3s1
Virtualisierung: KVM/libvirt
LoadBalancer vor der Kubernetes API: HAProxy
Ingress Controller: Traefik


Weitere Komponenten wie 
- cert-manager
- Longhorn
- PostgreSQL
- Keycloak
- Fleet
- Sealed Secrets
- Ansible 

beschreibe ich in den anderen Abschnitten.

Vorteile:

- Es gibt getrennte Server Nodes und Worker Nodes.
- Ingress, Storage, Services, StatefulSets und cert-manager können realistischer getestet werden.
- Das Setup ist näher an einer produktionsnahen Kubernetes Umgebung als ein einfaches minikube Lab.
- K3s ist trotzdem relativ schlank und gut für lokale VMs geeignet.
- Das Setup lässt sich mit Ansible, Makefile und Fleet wiederholbar aufbauen.


Nachteile:

- Das Setup ist komplexer als mit minikube, kind etc.
- Es verbraucht mehr lokale Ressourcen.
- Die Einrichtung dauert länger.
- Let’s Encrypt ist lokal nicht direkt möglich, da keine öffentliche Domain oder DNS Challenge vorhanden ist.


## 1.2 Cluster Konfiguration

Das Cluster läuft lokal auf virtuellen Maschinen.

Es gibt insgesamt sieben VMs, mit folgender Struktur:

k3s-lb-1       192.168.122.10   HAProxy LoadBalancer

k3s-server-1   192.168.122.11   Control Plane
k3s-server-2   192.168.122.12   Control Plane
k3s-server-3   192.168.122.13   Control Plane

k3s-agent-1    192.168.122.21   Worker
k3s-agent-2    192.168.122.22   Worker
k3s-agent-3    192.168.122.23   Worker


Die Server Nodes werden mit einem NoSchedule Taint erstellt. 
Normale Workloads laufen daher auf den Worker Nodes.

Die VMs werden über Skripte erstellt:

1. cluster/libvirt/00-bootstrap.sh
2. cluster/libvirt/01-deploy-cluster-cloudimg.sh
3. cluster/libvirt/99-cleanup.sh


00-bootstrap.sh: prüft die lokale Virtualisierung und installiert benötigte Pakete.
01-deploy-cluster-cloudimg.sh erstellt die VMs auf Basis eines Ubuntu Cloud Images. Die VMs bekommen feste IP Adressen, feste MAC Adressen und feste Ressourcen für RAM, CPU und Disk.
99-cleanup.sh entfernt die VMs wieder. Dabei werden auch VM Disks, Seed ISOs, DHCP Reservierungen, SSH Einträge und cloud-init Dateien entfernt.

Das Base Image bleibt standardmäßig erhalten. Wenn es ebenfalls gelöscht werden soll:


REMOVE_BASE_IMAGE=1 ./99-cleanup.sh


Die VMs sind werden so angelegt:

| Host | IP | MAC | RAM | vCPU | Disk |
|---|---|---|---:|---:|---:|
| k3s-lb-1 | 192.168.122.10 | 52:54:00:00:00:10 | 2048 MB | 1 | 20 GB |
| k3s-server-1 | 192.168.122.11 | 52:54:00:00:00:11 | 6144 MB | 2 | 40 GB |
| k3s-server-2 | 192.168.122.12 | 52:54:00:00:00:12 | 6144 MB | 2 | 40 GB |
| k3s-server-3 | 192.168.122.13 | 52:54:00:00:00:13 | 6144 MB | 2 | 40 GB |
| k3s-agent-1 | 192.168.122.21 | 52:54:00:00:00:21 | 10240 MB | 2 | 60 GB |
| k3s-agent-2 | 192.168.122.22 | 52:54:00:00:00:22 | 10240 MB | 2 | 60 GB |
| k3s-agent-3 | 192.168.122.23 | 52:54:00:00:00:23 | 10240 MB | 2 | 60 GB |

Die Agent Nodes haben mehr RAM und Disk, weil dort die Workloads laufen sollen.

## 1.3 Beispielhafte Cluster Struktur

Die Struktur sieht so aus:

```text
Host
└── KVM/libvirt
    ├── k3s-lb-1
    │   └── HAProxy
    └── K3s Cluster
        ├── k3s-server-1
        ├── k3s-server-2
        ├── k3s-server-3
        ├── k3s-agent-1
        ├── k3s-agent-2
        └── k3s-agent-3

Kubernetes
├── cattle-fleet-system
│   └── Fleet Controller
├── fleet-local
│   └── GitRepo und Bundles
├── cert-manager
│   └── cert-manager, webhook, cainjector
├── longhorn-system
│   └── Longhorn Storage Komponenten
├── postgresql
│   └── PostgreSQL für Keycloak
├── traefik
│   └── Traefik Ingress Controller
├── keycloak
│   └── Keycloak, Ingress und TLS Certificate
└── kube-system
    └── Kubernetes Komponenten und Sealed Secrets Controller
```

Die Komponenten werden nicht manuell einzeln deployed, sondern über Fleet und Helm aus dem GitHub Repository.

## 1.4 Kubernetes Kontext und Zugriff

Nach dem Cluster Setup wird die Kubeconfig auf den lokalen Host kopiert.

Pfad:
cluster/ansible/k3s.yaml
Die Datei wird per .gitignore ausgeschlossen.

Nutzung:

```bash
export KUBECONFIG=cluster/ansible/k3s.yaml
kubectl get nodes -o wide
```

Die Kubeconfig zeigt auf den HAProxy LoadBalancer mit der IP 192.168.122.10:6443

Validierung:
```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl get namespaces
kubectl get pods -A -o wide
kubectl get storageclass
```


## 1.5 Namespaces

Ich trenne die Komponenten bewusst über Namespaces.

Relevante Namespaces:

```text
cattle-fleet-system
fleet-local
cert-manager
longhorn-system
postgresql
traefik
keycloak
kube-system
```

Bedeutung:

```text
cert-manager
Namespace für cert-manager

longhorn-system
Namespace für Longhorn, CSI Komponenten und Storage Controller.

postgresql
Namespace für die Keycloak Datenbank und die Datenbank Secrets.

traefik
Namespace für den Ingress Controller.

keycloak
Namespace für Keycloak, Keycloak Secrets, Ingress und TLS Zertifikat.

fleet-local und cattle-fleet-system
Namespaces für Fleet GitOps.

kube-system
Kubernetes System Namespace. Zusätzlich läuft dort der Sealed Secrets Controller.
```

Diese Trennung macht das Setup übersichtlicher. 
Außerdem liegen Secrets und Anwendungen nicht alle im gleichen Namespace.
NAmespaces in Kubernetes sind wichtig zum logischen Trennen von Komponenten, Secrets, Zugriffen etc. 

## 1.6 Netzwerk und Service Modell

Das Netzwerk läuft über das libvirt default Netzwerk:

```text
192.168.122.0/24
```

Der zentrale Einstiegspunkt ist:

```text
k3s-lb-1
192.168.122.10
```

HAProxy übernimmt zwei Aufgaben.

Erstens Kubernetes API:

```text
Host --> 192.168.122.10:6443 --> HAProxy -->
--> k3s-server-1:6443
--> k3s-server-2:6443
--> k3s-server-3:6443
```

Zweitens HTTP und HTTPS für Anwendungen:

```text
Host --> 192.168.122.10:80 oder 443 --> HAProxy --> Traefik NodePort auf den Agent Nodes --> Ingress --> Service --> Pod
```

Traefik läuft als NodePort Service.

Verwendete NodePorts:

```text
HTTP: 30080
HTTPS: 30443
```

HAProxy leitet Port 80 und 443 weiter:

```text
192.168.122.10:80
--> 192.168.122.21:30080
--> 192.168.122.22:30080
--> 192.168.122.23:30080

192.168.122.10:443
--> 192.168.122.21:30443
--> 192.168.122.22:30443
--> 192.168.122.23:30443
```

Normale Anwendungen werden nicht direkt per NodePort veröffentlicht. Der Einstieg läuft über Traefik und Ingress.

Interne Services bleiben ClusterIP.

Prüfen:

```bash
kubectl get services -A -o wide
kubectl get ingress -A -o wide
```

## 1.7 Ingress Controller

Ich verwende Traefik als Ingress Controller.

K3s bringt Traefik standardmäßig mit. 
Ich habe das Standard Traefik aber deaktiviert, damit Traefik vollständig über Helm und das Repository verwaltet wird.

Traefik läuft im Namespace:

```text
traefik
```

Der Wrapper Chart liegt hier:

```text
platform/traefik
```

Wichtige Werte:

```yaml
traefik:
  deployment:
    replicas: 2

  service:
    enabled: true
    single: true
    spec:
      type: NodePort

  ports:
    web:
      port: 80
      exposedPort: 80
      nodePort: 30080
      expose:
        default: true

    websecure:
      port: 443
      exposedPort: 443
      nodePort: 30443
      expose:
        default: true

  ingressClass:
    enabled: true
    isDefaultClass: true

  providers:
    kubernetesCRD:
      enabled: true
      ingressClass: traefik

    kubernetesIngress:
      enabled: true
      ingressClass: traefik
```

IngressClass:

```text
traefik
```

Validierung:

```bash
kubectl get pods -n traefik
kubectl get svc -n traefik
kubectl get ingressclass
```

## 1.8 DNS und lokale Hostnamen

Keycloak ist lokal über diesen Hostnamen erreichbar:

```text
keycloak.local.example
```

Da es ein lokales Setup ist, wird der Name über `/etc/hosts` auf den HAProxy LoadBalancer gelegt.

Eintrag auf dem Host:

```text
192.168.122.10 keycloak.local.example
```

Der Traffic läuft dann so:

```text
Browser --> /etc/hosts --> 192.168.122.10:443 --> HAProxy --> Traefik NodePort 30443 --> Ingress keycloak.local.example --> Keycloak Service --> Keycloak Pod
```

URL:

```text
https://keycloak.local.example
```

## 1.9 Storage

K3s bringt standardmäßig `local-path` als StorageClass mit.

Zusätzlich installiere ich Longhorn.

Prüfen:

```bash
kubectl get storageclass
kubectl get pvc -A
kubectl get pv
```

Verwendete StorageClasses:

```text
local-path
longhorn
longhorn-static
```

PostgreSQL nutzt Longhorn.

Keycloak selbst braucht keinen eigenen persistenten Storage, weil die relevanten Daten in PostgreSQL gespeichert werden.

PostgreSQL PVC:

```yaml
primary:
  persistence:
    enabled: true
    storageClass: longhorn
    size: 10Gi
```

Warum Longhorn:
Die Keycloak Daten sollen nicht verloren gehen, wenn der Keycloak Pod neu erstellt wird.
PostgreSQL soll persistenten Storage nutzen.
Longhorn ist für ein lokales Multi Node Setup realistischer als nur local-path.

## 1.10 Kubernetes Secrets und sensible Daten

Admin Passwörter, Datenbankpasswörter und andere sensible Werte liegen nicht im Klartext im Git Repository.

Ich verwende dafür Sealed Secrets.

Der Sealed Secrets Controller läuft im Namespace:

```text
kube-system
```

Wrapper Chart:

```text
platform/sealed-secrets
```

Verschlüsselte Secrets:

```text
platform/secrets
```
SealedSecret Dateien:

```text
keycloak-admin.sealedsecret.yaml
keycloak-database.sealedsecret.yaml
keycloak-postgresql-auth.sealedsecret.yaml
```

Diese Dateien dürfen ins Git Repository, weil sie verschlüsselt sind.

Secrets prüfen:

```bash
kubectl get secrets -A
kubectl get secret keycloak-admin -n keycloak
kubectl get secret keycloak-database -n keycloak
kubectl get secret keycloak-postgresql-auth -n postgresql
```

Admin Passwort auslesen:

```bash
kubectl get secret keycloak-admin -n keycloak \
  -o jsonpath="{.data.admin-password}" | base64 -d; echo
```

Wichtig ist der private Key vom Sealed Secrets Controller.

Wenn das Cluster neu gebaut wird und dieser Key nicht wiederhergestellt wird, können die vorhandenen SealedSecret Dateien nicht mehr entschlüsselt werden.

Typischer Fehler:

```text
no key could decrypt secret
```

Key sichern:

```bash
mkdir -p .local-secrets

kubectl -n kube-system get secret \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > .local-secrets/sealed-secrets-key-backup.yaml

chmod 600 .local-secrets/sealed-secrets-key-backup.yaml
```

Die Datei liegt nicht im Git:

```text
.local-secrets/sealed-secrets-key-backup.yaml
```

Key wiederherstellen:

```bash
kubectl apply -f .local-secrets/sealed-secrets-key-backup.yaml
kubectl -n kube-system rollout restart deployment sealed-secrets-controller
```

Wenn kein Backup vorhanden ist, müssen die Secrets neu erzeugt und neu mit kubeseal versiegelt werden!

## 1.11 Resource Requests und Limits

Ich setze Resource Requests und Limits für die zentralen Komponenten.

Für diese Aufgabe sind das vor allem:

```text
Keycloak
PostgreSQL
```

Keycloak:

```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 1500m
    memory: 2Gi
```

PostgreSQL:

```yaml
resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi
```
Die Ressourcen werden so begrenzt und Kubernetes kann die Nodes leichter zuweisen die am besten passen. 

Prüfen:

```bash
kubectl describe pod keycloak-0 -n keycloak | grep -A8 "Limits:"
kubectl describe pod postgresql-0 -n postgresql | grep -A8 "Limits:"
```

## 1.12 Health Checks

Für Keycloak sind Startup, Readiness und Liveness Probes aktiviert.

Startup Probe:

```yaml
startupProbe:
  enabled: true
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 1
  failureThreshold: 30
  successThreshold: 1
```

Readiness Probe:

```yaml
readinessProbe:
  enabled: true
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 1
  failureThreshold: 3
  successThreshold: 1
```

Liveness Probe:

```yaml
livenessProbe:
  enabled: true
  initialDelaySeconds: 120
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
  successThreshold: 1
```
Bedeutung der wichtigsten Werte:

- initialDelaySeconds
Zeit in Sekunden, die Kubernetes nach dem Container Start wartet, bevor die erste Prüfung ausgeführt wird.

- periodSeconds
Intervall in Sekunden, in dem Kubernetes die Prüfung wiederholt.

- timeoutSeconds
Zeit in Sekunden, wie lange Kubernetes auf eine Antwort der Probe wartet.

- failureThreshold
Anzahl der fehlgeschlagenen Prüfungen, bevor Kubernetes die Probe als fehlgeschlagen bewertet.

- successThreshold
Anzahl der erfolgreichen Prüfungen, bevor Kubernetes die Probe als erfolgreich bewertet.


Kubernetes wartet zuerst 30 Sekunden.
Danach wird alle 10 Sekunden geprüft.
Keycloak darf dabei bis zu 30 mal nicht erfolgreich antworten.
Dadurch bekommt Keycloak beim Start genug Zeit.
Wenn die Startup Probe erfolgreich ist, werden Readiness und Liveness relevant.

Die Readiness Probe prüft, ob Keycloak bereit ist Traffic anzunehmen.
Wenn diese Probe fehlschlägt, bleibt der Pod zwar gestartet, bekommt aber keinen Traffic über den Service.
Das ist wichtig, damit Kubernetes keinen Traffic an einen Pod sendet, der noch nicht bereit ist.

Die Liveness Probe prüft, ob der Container noch gesund läuft.
Wenn diese Probe mehrfach fehlschlägt, startet Kubernetes den Container neu.
Das hilft bei Situationen, in denen der Prozess zwar noch läuft, aber nicht mehr sauber reagiert.

Ich habe die Startup Probe bewusst großzügiger gesetzt, weil Keycloak beim Start manchmal länger braucht. 
Gerade mit externer Datenbank, Initialisierung und lokalen Ressourcen kann der Start länger dauern.

Zusätzlich gibt es einen Init Container, der wartet, bis PostgreSQL erreichbar ist.

```yaml
initContainers:
  - name: wait-for-postgresql
    image: busybox:1.36
    command:
      - sh
      - -c
      - |
        until nc -z postgresql.postgresql.svc.cluster.local 5432; do
          echo "Warte auf PostgreSQL..."
          sleep 5
        done
        echo "PostgreSQL ist erreichbar"
```

Damit startet Keycloak erst weiter, wenn die Datenbank erreichbar ist.

Prüfen:

```bash
kubectl get pods -n keycloak
kubectl describe pod keycloak-0 -n keycloak
kubectl logs keycloak-0 -n keycloak
```

## 1.13 Cluster Lifecycle

Das Setup kann über das Makefile aufgebaut, validiert und gelöscht werden.

Wichtige Targets:

```text
make vm-create
make cluster-create
make fleet-bootstrap
make install
make validate
make cleanup
```

Bedeutung:

```text
make vm-create
Erstellt die lokalen VMs.

make cluster-create
Erstellt das K3s Cluster per Ansible.

make fleet-bootstrap
Installiert Fleet und verbindet das Cluster mit dem Git Repository.

make install
Führt vm-create, cluster-create und fleet-bootstrap aus.

make validate
Zeigt Nodes, Pods und Fleet Status.

make cleanup
Entfernt Cluster und VMs.
```

# 2. Helm

## 2.1 Erwartete Helm Komponenten

Alle zentralen Plattform Komponenten werden per Helm installiert.

Ich verwende Wrapper Charts unter `platform/`.

Im Repository liegt nicht der komplette Chart Code der Anwendung.
Im Repository liegt ein kleines eigenes Chart.
Dieses Chart referenziert das eigentliche Helm Chart als Dependency.


Per Helm werden installiert:

```text
cert-manager
Sealed Secrets
Longhorn
PostgreSQL
Traefik
Keycloak
```

Fleet selbst wird ebenfalls per Helm installiert, aber beim Bootstrap über Ansible.

Verwendete Charts:

| Komponente | Repository | Chart Version |
|---|---|---:|
| cert-manager | oci://quay.io/jetstack/charts | v1.20.2 |
| Sealed Secrets | https://bitnami-labs.github.io/sealed-secrets | 2.17.3 |
| Longhorn | https://charts.longhorn.io | 1.11.2 |
| PostgreSQL | https://charts.bitnami.com/bitnami | 18.6.6 |
| Traefik | https://traefik.github.io/charts | 40.2.0 |
| Keycloak | https://charts.bitnami.com/bitnami | 25.2.0 |

## 2.2 Helm Values

Die relevanten Values liegen unter:

```text
platform/cert-manager/values.yaml
platform/sealed-secrets/values.yaml
platform/longhorn/values.yaml
platform/postgresql/values.yaml
platform/traefik/values.yaml
platform/keycloak/values.yaml
```

Beispiel Keycloak Wrapper Chart:

```yaml
apiVersion: v2
name: keycloak-wrapper
description: Wrapper Chart for Keycloak
type: application
version: 0.1.0

dependencies:
  - name: keycloak
    version: 25.2.0
    repository: https://charts.bitnami.com/bitnami
```

Beispiel Keycloak Values:

```yaml
keycloak:
  image:
    registry: docker.io
    repository: bitnamilegacy/keycloak
    tag: 26.3.3-debian-12-r0

  auth:
    adminUser: admin
    existingSecret: keycloak-admin
    passwordSecretKey: admin-password

  production: true
  proxyHeaders: xforwarded
  hostnameStrict: false

  postgresql:
    enabled: false

  externalDatabase:
    host: postgresql.postgresql.svc.cluster.local
    port: 5432
    user: keycloak
    database: keycloak
    existingSecret: keycloak-database
    existingSecretPasswordKey: password

  service:
    type: ClusterIP

  ingress:
    enabled: true
    ingressClassName: traefik
    hostname: keycloak.local.example
    path: /
    pathType: Prefix
    servicePort: http
    tls: true
    annotations:
      cert-manager.io/cluster-issuer: selfsigned-cluster-issuer
```

## 2.3 Helm Installation dokumentieren

Normalerweise übernimmt Fleet die Installation.

Trotzdem können die Komponenten auch manuell installiert werden.

Beispiel cert-manager:

```bash
helm dependency update platform/cert-manager

helm upgrade --install cert-manager platform/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --values platform/cert-manager/values.yaml
```

Beispiel PostgreSQL:

```bash
helm dependency update platform/postgresql

helm upgrade --install postgresql platform/postgresql \
  --namespace postgresql \
  --create-namespace \
  --values platform/postgresql/values.yaml
```

Beispiel Keycloak:

```bash
helm dependency update platform/keycloak

helm upgrade --install keycloak platform/keycloak \
  --namespace keycloak \
  --create-namespace \
  --values platform/keycloak/values.yaml
```

Validierung:

```bash
helm list -A
kubectl get pods -A
kubectl get services -A
kubectl get ingress -A
```

# 3. cert-manager und Let’s Encrypt

## 3.1 cert-manager Installation

cert-manager wird per Helm installiert.

Wrapper Chart:

```text
platform/cert-manager
```

Namespace:

```text
cert-manager
```

Die CRDs werden über die Values aktiviert:

```yaml
cert-manager:
  crds:
    enabled: true

  prometheus:
    enabled: false
```

Die CRDs sind notwendig, damit Ressourcen wie ClusterIssuer und Certificate verwendet werden können.
Da ich kein Monitoring habe ist Prometheus deinstalliert. 

Validierung:

```bash
kubectl get pods -n cert-manager
kubectl get crds | grep cert-manager
```

## 3.2 Issuer oder ClusterIssuer

Ich verwende einen ClusterIssuer.

Ein Issuer gilt nur in einem Namespace.
Ein ClusterIssuer gilt clusterweit.

Aktuell wird der ClusterIssuer nur für Keycloak verwendet. Da es aber ein Plattform Setup ist, kann derselbe ClusterIssuer später auch für weitere Anwendungen genutzt werden.

Der ClusterIssuer liegt hier:

```text
platform/cert-manager-issuer/selfsigned-cluster-issuer.yaml
```

Inhalt:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-cluster-issuer
spec:
  selfSigned: {}
```

Validierung:

```bash
kubectl get clusterissuer
kubectl describe clusterissuer selfsigned-cluster-issuer
```

## 3.3 Let’s Encrypt in lokaler Umgebung

Let’s Encrypt kann Zertifikate nur ausstellen, wenn die Domain validiert werden kann.

Bei einem rein lokalen Hostnamen wie:

```text
keycloak.local.example
```

ist das nicht möglich.

Mein Browser kann den Namen nur auflösen, weil ich lokal einen `/etc/hosts` Eintrag gesetzt habe:

```text
192.168.122.10 keycloak.local.example
```

Let’s Encrypt kann diesen lokalen Namen aber nicht über das Internet erreichen.
--> Deshalb verwende ich in diesem Setup keine echte Let’s Encrypt Ausstellung.

## 3.4 Lokale Alternative mit selfsigned Zertifikat (Alternative C)

Für dieses lokale Setup verwende ich einen selfsigned ClusterIssuer über cert-manager.

Das Zertifikat für Keycloak wird durch cert-manager erzeugt.

Prüfen:

```bash
kubectl get certificate -n keycloak
kubectl get secret keycloak.local.example-tls -n keycloak
```

Da es ein selbstsigniertes Zertifikat ist, vertraut der Browser dem Zertifikat nicht automatisch.


## 3.5 Zertifikatsvalidierung

Prüfen:

```bash
kubectl get clusterissuer
kubectl get certificate -A
kubectl get certificaterequest -A
kubectl describe certificate keycloak.local.example-tls -n keycloak
kubectl get secret keycloak.local.example-tls -n keycloak
```

HTTPS Test:

```bash
https://keycloak.local.example im Browser öffnen
```

## 3.6 Produktives Zielbild mit Let’s Encrypt

In einer Umgebung mit echter Domain würde ich Let’s Encrypt über HTTP-01 oder DNS-01 nutzen.

HTTP-01 wäre möglich, wenn die Domain öffentlich erreichbar ist und Port 80 bis zum Ingress Controller weitergeleitet wird.

Beispiel:

```text
Let’s Encrypt
--> öffentliche Domain
--> Cloudflare Tunnel oder Reverse Proxy
--> Traefik
--> cert-manager Solver
--> Solver Pod
```

DNS-01 wäre sinnvoll, wenn das Cluster nicht direkt öffentlich erreichbar ist.

Beispiel:

```text
Let’s Encrypt
--> DNS Provider API
--> TXT Record wird gesetzt
--> Domain wird validiert
--> Zertifikat wird ausgestellt
```

Für dieses lokale Setup habe ich keine passende öffentliche Domain und keine DNS Credentials.

# 4. Keycloak Deployment

## 4.1 Helm Chart

Keycloak wird per Helm installiert.

Ich verwende das Bitnami Keycloak Chart über ein eigenes Wrapper Chart.

Wrapper Chart:

```text
platform/keycloak/Chart.yaml
```

Inhalt:

```yaml
apiVersion: v2
name: keycloak-wrapper
description: Wrapper Chart for Keycloak
type: application
version: 0.1.0

dependencies:
  - name: keycloak
    version: 25.2.0
    repository: https://charts.bitnami.com/bitnami
```

## 4.2 Keycloak Konfiguration

Wichtige Einstellungen:

```text
Admin User: admin
Admin Passwort: Kubernetes Secret keycloak-admin
Hostname: keycloak.local.example
Service: ClusterIP
IngressClass: traefik
TLS: aktiv
Datenbank: externe PostgreSQL Installation
Resources: gesetzt
Probes: gesetzt
```

Der Keycloak Service ist nicht direkt von außen erreichbar.

Der Zugriff erfolgt über:

```text
HAProxy
--> Traefik
--> Ingress
--> Keycloak Service
--> Keycloak Pod
```

## 4.3 Datenbank

Keycloak verwendet PostgreSQL.

PostgreSQL läuft als separates Helm Release im Namespace:

```text
postgresql
```

Keycloak erreicht PostgreSQL über den internen Service Namen:

```text
postgresql.postgresql.svc.cluster.local
```

Die Datenbank Werte in Keycloak:

```yaml
externalDatabase:
  host: postgresql.postgresql.svc.cluster.local
  port: 5432
  user: keycloak
  database: keycloak
  existingSecret: keycloak-database
  existingSecretPasswordKey: password
```

PostgreSQL nutzt persistenten Storage über Longhorn.

Das ist besser als eine eingebettete Datenbank oder reiner Entwicklungsmodus, weil die Daten nicht am Keycloak Pod hängen.

## 4.4 Zugriff auf Keycloak

URL:

```text
https://keycloak.local.example
```

Lokaler DNS Eintrag:

```text
192.168.122.10 keycloak.local.example
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

## 4.5 Keycloak Funktionstest

Prüfschritte:

```bash
kubectl get pods -n keycloak
kubectl get svc -n keycloak
kubectl get ingress -n keycloak
kubectl get certificate -n keycloak
kubectl logs keycloak-0 -n keycloak
curl -vk https://keycloak.local.example
```
alternativ per Browser einloggen

Erwartung:


Keycloak Pod läuft.
PostgreSQL Pod läuft.
Service ist vorhanden.
Ingress ist vorhanden.
Certificate ist Ready.
TLS Secret existiert.
Admin Console ist über HTTPS erreichbar.
Login mit admin User funktioniert.


# 5. Ingress und HTTPS

## 5.1 Ingress Konfiguration

Keycloak wird über den Ingress aus dem Helm Chart veröffentlicht.

Wichtige Werte:

```yaml
ingress:
  enabled: true
  ingressClassName: traefik
  hostname: keycloak.local.example
  path: /
  pathType: Prefix
  servicePort: http
  tls: true
  annotations:
    cert-manager.io/cluster-issuer: selfsigned-cluster-issuer
```

Dadurch erstellt das Chart einen Ingress für Keycloak.

Die cert-manager Annotation sorgt dafür, dass cert-manager das Zertifikat über den ClusterIssuer erzeugt.

## 5.2 HTTPS

Das TLS Secret heißt:

```text
keycloak.local.example-tls
```

Namespace:

```text
keycloak
```

Prüfen:

```bash
kubectl get secret keycloak.local.example-tls -n keycloak
kubectl describe ingress -n keycloak
kubectl get certificate -n keycloak
```

Der HTTPS Zugriff läuft über:

```text
Client
--> keycloak.local.example
--> 192.168.122.10:443
--> HAProxy
--> Traefik NodePort 30443
--> Keycloak Ingress
--> Keycloak Service
--> Keycloak Pod
```



# 6. Repository Struktur

Die Struktur so aufgebaut:

```text
local-kubernetes-keycloak-platform/
├── Makefile
├── README.md
├── cluster/
│   ├── libvirt/
│   └── ansible/
├── docs/
│   └── Fragen_beantworten.md
├── fleet/
│   └── gitrepo.yaml
├── platform/
│   ├── cert-manager/
│   ├── cert-manager-issuer/
│   ├── keycloak/
│   ├── longhorn/
│   ├── postgresql/
│   ├── sealed-secrets/
│   ├── secrets/
│   └── traefik/
├── .local-secrets/
└── tmp/
```

Hinweis:

```text
.local-secrets liegt auf .gitignore.
tmp liegt auf .gitignore.
cluster/ansible/k3s.yaml liegt auf .gitignore.
cluster/ansible/.k3s-bootstrap-token liegt auf .gitignore.
```

Das Makefile ist der Einstiegspunkt:

```makefile
.PHONY: vm-create vm-delete cluster-create cluster-delete fleet-bootstrap fleet-status install validate cleanup

vm-create:
	cd cluster/libvirt && ./00-bootstrap.sh
	cd cluster/libvirt && ./01-deploy-cluster-cloudimg.sh

vm-delete:
	cd cluster/libvirt && ./99-cleanup.sh

cluster-create:
	cd cluster/ansible && ansible-playbook site.yml

cluster-delete:
	cd cluster/ansible && ansible-playbook uninstall.yml

fleet-bootstrap:
	cd cluster/ansible && ansible-playbook bootstrap-fleet.yml

fleet-status:
	KUBECONFIG=cluster/ansible/k3s.yaml kubectl get gitrepo,bundles,bundledeployments -A
	KUBECONFIG=cluster/ansible/k3s.yaml kubectl get pods -A

install: vm-create cluster-create fleet-bootstrap

validate:
	KUBECONFIG=cluster/ansible/k3s.yaml kubectl get nodes -o wide
	KUBECONFIG=cluster/ansible/k3s.yaml kubectl get pods -A
	KUBECONFIG=cluster/ansible/k3s.yaml kubectl get gitrepo,bundles,bundledeployments -A

cleanup: cluster-delete vm-delete
```

# 7. Dokumentation

## 7.1 Voraussetzungen

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
```

Außerdem wird benötigt:

```text
Linux Host mit KVM/libvirt
aktivierte CPU Virtualisierung
libvirt default network
SSH Zugriff auf die VMs nach Erstellung
ausreichend RAM und CPU
```

## 7.2 Setup Anleitung

Aus dem Repository Root:

```bash
make install
```

Das führt aus:

```text
make vm-create
make cluster-create
make fleet-bootstrap
```

Danach übernimmt Fleet die Installation der Plattform Komponenten.

Status prüfen:

```bash
make validate
make fleet-status
```

Einzelne Schritte:

```bash
make vm-create
make cluster-create
make fleet-bootstrap
make validate
make cleanup
```

## 7.3 Architekturüberblick

Kurzform:

```text
Lokaler Host
--> KVM/libvirt VMs
--> HAProxy LoadBalancer
--> K3s Multi Node Cluster
--> Fleet
--> Helm Plattform Komponenten
--> Traefik
--> Keycloak
--> PostgreSQL
--> Longhorn Storage
```

## 7.4 Zugriff auf Keycloak

URL:

```text
https://keycloak.local.example
```

Notwendiger `/etc/hosts` Eintrag:

```text
192.168.122.10 keycloak.local.example
```

Admin User:

```text
admin
```

Admin Passwort:

```bash
kubectl get secret keycloak-admin -n keycloak \
  -o jsonpath="{.data.admin-password}" | base64 -d; echo
```

## 7.5 Validierung

Cluster prüfen:

```bash
export KUBECONFIG=cluster/ansible/k3s.yaml

kubectl cluster-info
kubectl get nodes -o wide
kubectl get namespaces
kubectl get pods -A -o wide
```

Fleet prüfen:

```bash
kubectl get gitrepo -A
kubectl get bundles -n fleet-local
kubectl get bundledeployments -A
```

Helm prüfen:

```bash
helm list -A
```

Storage prüfen:

```bash
kubectl get storageclass
kubectl get pvc -A
kubectl get pv
```

cert-manager prüfen:

```bash
kubectl get pods -n cert-manager
kubectl get crds | grep cert-manager
kubectl get clusterissuer
kubectl get certificate -A
```

Traefik prüfen:

```bash
kubectl get pods -n traefik
kubectl get svc -n traefik
kubectl get ingressclass
```

Keycloak prüfen:

```bash
kubectl get pods -n keycloak
kubectl get svc -n keycloak
kubectl get ingress -n keycloak
kubectl get certificate -n keycloak
kubectl logs keycloak-0 -n keycloak
```

HTTPS prüfen:

```bash
curl -vk https://keycloak.local.example
```

## 7.6 Troubleshooting

Kubernetes API nicht erreichbar:

```bash
export KUBECONFIG=cluster/ansible/k3s.yaml
kubectl get nodes
```

Mögliche Ursachen:

```text
HAProxy läuft nicht.
K3s Server Nodes laufen nicht.
Kubeconfig zeigt auf die falsche IP.
Libvirt Netzwerk ist nicht aktiv.
```

Nützliche Befehle:

```bash
virsh net-list --all
ssh k3sadmin@k3s-lb-1
sudo systemctl status haproxy
ssh k3sadmin@k3s-server-1
sudo systemctl status k3s
```

Fleet synchronisiert nicht:

```bash
kubectl get gitrepo -A
kubectl get bundles -n fleet-local
kubectl get bundledeployments -A
kubectl get pods -n cattle-fleet-system
```

Sealed Secrets werden nicht entschlüsselt:

```bash
kubectl get sealedsecrets -A
kubectl get pods -n kube-system | grep sealed
kubectl logs -n kube-system deployment/sealed-secrets-controller
```

Typischer Fehler:

```text
no key could decrypt secret
```

Keycloak startet nicht:

```bash
kubectl get pods -n keycloak
kubectl describe pod keycloak-0 -n keycloak
kubectl logs keycloak-0 -n keycloak
```

Mögliche Ursachen:

```text
PostgreSQL ist nicht erreichbar.
Keycloak Datenbank Secret fehlt.
Admin Secret fehlt.
Hostname oder Proxy Einstellung ist falsch.
```

Zertifikat wird nicht erstellt:

```bash
kubectl get certificate -A
kubectl describe certificate keycloak.local.example-tls -n keycloak
kubectl get clusterissuer
kubectl describe clusterissuer selfsigned-cluster-issuer
kubectl logs -n cert-manager deployment/cert-manager
```

Keycloak ist im Browser nicht erreichbar:

```bash
cat /etc/hosts
kubectl get ingress -n keycloak
kubectl get svc -n traefik
curl -vk https://keycloak.local.example
```

Erwarteter hosts Eintrag:

```text
192.168.122.10 keycloak.local.example
```

# 8. Annahmen und Einschränkungen

## 8.1 Verwendetes Betriebssystem

Das Setup wurde für einen Linux Host mit KVM/libvirt gebaut.

Verwendet:

```text
Host OS: Ubuntu 26.04 LTS
VM OS: Ubuntu 22.04.5 LTS
```

## 8.2 Verfügbare lokale Ressourcen

Das Setup benötigt deutlich mehr Ressourcen als ein einfaches Single Node Lab.

Das liegt vor allem an:

```text
3 Server Nodes
3 Agent Nodes
Longhorn
PostgreSQL
Keycloak
Traefik
Fleet
```

Für kleinere Rechner wäre ein Single Node Setup mit kind oder minikube einfacher.

## 8.3 DNS

Die lokale Domain funktioniert nur über `/etc/hosts`.

```text
192.168.122.10 keycloak.local.example
```

## 8.4 TLS und Let’s Encrypt

Let’s Encrypt wird lokal nicht echt verwendet.

Grund:

```text
keycloak.local.example ist nicht öffentlich erreichbar.
Let’s Encrypt kann die Domain nicht validieren.
Es gibt keine DNS Challenge mit echtem DNS Provider.
```

Deshalb wird lokal ein selfsigned ClusterIssuer über cert-manager genutzt.

Der Browser wird dem Zertifikat nicht automatisch vertrauen.

## 8.5 Unterschiede zu Produktion

Für eine produktive oder produktionsnähere Umgebung würde ich zusätzlich machen:

```text
feste Image Tags für alle Images
echtes Let’s Encrypt über DNS-01 oder HTTP-01
echte Domain
Backup und Restore Konzept für PostgreSQL
Backup und Restore Konzept für Longhorn
Monitoring mit Prometheus und Grafana
Logging Konzept
ResourceQuotas und LimitRanges
getrennte Umgebungen für lokal, staging und produktion
```

# 9. Optional
## 9.1 Fleet und GitOps

Ich verwende Fleet als GitOps Lösung.

Das Repository ist dadurch die gewünschte Quelle für die Plattform Installation.

GitRepo Resource:

```text
fleet/gitrepo.yaml
```

Die GitRepo Resource synchronisiert diese Pfade:

```text
platform/cert-manager
platform/cert-manager-issuer
platform/longhorn
platform/postgresql
platform/traefik
platform/keycloak
platform/sealed-secrets
platform/secrets
```

Die Reihenfolge wird über `dependsOn` in den Fleet Dateien gesteuert.

Beispiel Keycloak:

```yaml
defaultNamespace: keycloak

dependsOn:
  - name: local-keycloak-platform-platform-postgresql
    acceptedStates:
      - Ready
      - Modified
  - name: local-keycloak-platform-platform-traefik
  - name: local-keycloak-platform-platform-secrets

helm:
  releaseName: keycloak
```

## 9.2 Sealed Secrets

Ich verwende Sealed Secrets, damit sensible Werte nicht im Klartext im Git Repository liegen.

Das betrifft vor allem:

```text
Keycloak Admin Passwort
Keycloak Datenbank Passwort
PostgreSQL Admin Passwort
```

Wichtig ist dabei der Ablauf beim ersten Benutzen.

Die Sealed Secrets Dateien werden nicht automatisch beim ersten Start erzeugt. 
Sie müssen einmal manuell erstellt, mit `kubeseal` verschlüsselt und danach an der richtigen Stelle im Repository abgelegt werden.

```text
platform/secrets/
```

Aktuelle Dateien:

```text
keycloak-admin.sealedsecret.yaml
keycloak-database.sealedsecret.yaml
keycloak-postgresql-auth.sealedsecret.yaml
```

Der Ablauf beim ersten Erstellen ist:

```text
1. Normale Kubernetes Secrets lokal mit kubectl erzeugen
2. Diese Secrets nicht ins Git legen!
3. Die Secrets mit kubeseal gegen den Sealed Secrets Controller verschlüsseln
4. Die erzeugten SealedSecret Dateien unter platform/secrets ablegen
5. Die temporären Klartext Secret Dateien wieder löschen
6. Änderungen committen und pushen
7. Fleet synchronisiert die SealedSecret Dateien ins Cluster
8. Der Sealed Secrets Controller erzeugt daraus die echten Kubernetes Secrets
9. Den Sealed Secrets private key sichern
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

Wichtig ist außerdem, dass der private Key des Sealed Secrets Controllers gesichert wird!

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


## 9.3 Longhorn

Ich verwende Longhorn für den persistenten PostgreSQL Storage.

Keycloak selbst speichert keine relevanten Daten im Pod. Die Daten liegen in PostgreSQL.

## 9.4 PostgreSQL als separates Helm Release

PostgreSQL ist nicht als Subchart innerhalb von Keycloak aktiviert.

Stattdessen läuft PostgreSQL als eigenes Helm Release.

Grund:

```text
Die Datenbank ist klar getrennt.
PostgreSQL hat eigene Values.
PostgreSQL hat eigene Secrets.
PostgreSQL hat eigenen Storage.
Die Abhängigkeit zu Keycloak ist über Fleet sichtbar.
```

# 10. Fazit

Die Aufgabe ist aus meiner Sicht technisch erfüllt.

Das Setup enthält:

```text
lokales Kubernetes Cluster
mehrere Nodes
Namespaces
Deployments und StatefulSets
Services
Ingress
Secrets
ConfigMaps
PersistentVolumes und PVCs
cert-manager CRDs
Helm Installation
Traefik Ingress Controller
TLS über cert-manager
Keycloak über HTTPS
PostgreSQL als Datenbank
Sealed Secrets für sensible Werte
Makefile für Setup, Validierung und Cleanup
Fleet als GitOps Ansatz, der sicherlich noch verbessert werden kann. 
```

Die wichtigste Einschränkung ist Let’s Encrypt.

Da das Setup lokal ist und keine öffentliche Domain verwendet wird, kann Let’s Encrypt die Domain nicht validieren. Deshalb verwende ich lokal einen selfsigned ClusterIssuer über cert-manager und beschreibe zusätzlich, wie es mit echter Domain funktionieren würde.

Für mich war die Aufgabe nicht nur ein Keycloak Deployment, sondern auch eine gute Möglichkeit, ein lokales K3s Multi Node Setup mit GitOps, Storage, Secrets und Ingress aufzubauen.
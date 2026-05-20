# Local Kubernetes Keycloak Platform

Dieses Repository enthält ein lokales Kubernetes Setup mit K3s, Fleet, Helm, cert-manager, Longhorn, Traefik, PostgreSQL, Keycloak und Sealed Secrets.

Ziel ist es, ein lokales aber möglichst produktionsnahes Setup zu bauen, welches wiederholbar aufgebaut und auch wieder sauber entfernt werden kann.


# 1.1 Frage: Wahl der Kubernetes-Distribution

Ich habe mich für ein K3s Multi Node Setup entschieden, welches lokal auf meinem System läuft.

In der Vergangenheit habe ich ich private Setups zum lernen und testen mit minikube aufgebaut. Minikube würde, genauso wie das neue K3s Setup, die Anforderungen erfüllen. 
Aber für diese Aufgabe wollte ich ein Setup erstellen, welches möglichst nahe an einer produktiv Umgebung ist.

Das gesamte Setup ist "overkill" für die Aufgabe, aber da ich noch nie ein K3s Cluster aufgebaut habe, sah ich es als gute Möglichkeit zum lernen.

Trotzdem ist K3s relativ schlank und kann auf lokalen virtuellen Maschinen betrieben werden. 

Vorteile dieser Lösung:

- Es gibt Server Nodes und Worker Nodes.
- Ingress, Storage, Services, StatefulSets und cert-manager können realistischer getestet werden.
- Das Setup ist näher an produktionsnahen Kubernetes Umgebungen als ein reines minikube Lab.

Nachteile:

- Das Setup ist deutlich komplexer
- Es verbraucht mehr Resourcen
- Let’s Encrypt ist in einer rein lokalen Umgebung nicht ohne öffentliche Erreichbarkeit oder DNS Challenge nutzbar.

Verwendete Versionen:

- Kubernetes Distribution: K3s
- Kubernetes Version: v1.35.4+k3s1
- OS des Host: Ubuntu 26.04 LTS
- OS der VMs: Ubuntu 22.04.5 LTS
- Container Runtime: containerd://2.2.3-k3s1
- Lokale Virtualisierung: KVM/libvirt
- LoadBalancer vor der Kubernetes API: HAProxy

# 1.2 Cluster-Konfiguration
## Wie wird das Cluster erstellt?

Das Cluster wird in in vier Stufen erstellt.

### Erstellen der VMs
Dafür werden mit scripts virtuelle Maschinen auf KVM/libvrit Basis erstellt. Als Image verwende ich ein Ubuntu Cloud Image.
Die VMs erhalten feste IP Adressen, feste MAC Adressen und eine definierte Ressourcenzuweisung für RAM, vCPU und Disk. 
Dadurch ist das Setup reproduzierbar und kann nach einem Cleanup erneut mit derselben Struktur aufgebaut werden.

Es werden 7 Server erstellt:

|Server| IP | MAC | RAM | vCPU | Disk Size

Loadbalancer:
k3s-lb-1|192.168.122.10|52:54:00:00:00:10|2048|1|20 

Control-Plane:
k3s-server-1|192.168.122.11|52:54:00:00:00:11|6144|2|40 
k3s-server-2|192.168.122.12|52:54:00:00:00:12|6144|2|40
k3s-server-3|192.168.122.13|52:54:00:00:00:13|6144|2|40

Agents:
k3s-agent-1|192.168.122.21|52:54:00:00:00:21|10240|2|60
k3s-agent-2|192.168.122.22|52:54:00:00:00:22|10240|2|60
k3s-agent-3|192.168.122.23|52:54:00:00:00:23|10240|2|60

Es existieren drei Skripte:
1. 00-bootstrap.sh
Das Skript installiert die benötigten Virtualisierungspakete, prüft die CPU Virtualisierung, aktiviert libvirt, startet das default Netzwerk und prüft/erstellt einen SSH Key.

2. 01-deploy-cluster-cloudimg.sh
Ich verwende hier ein Unbuntu Cloud Image als Basis. Das Iamge wird heruntergeladen und lokal gespeichert. Dadurch muss nicht jede VM über einen vollständigen, langsamen Installer laufen. Da es sich um ein lokales Setup handelt verwenden die VMs das gleiche Base Image, aber eigene VM Disks. 
Die VMs erhalten unter anderen feste IP Adressen im libvrit default Netzwerk. 
Zusätzlich werden SSH Aliase erstellt damit die VMs direkt über Namen, anstatt nur IPs erreicht werden können.
Beim anlegen der VM wird nach einem admin passwort gefragt, welches nur während der runtime gehandhabt wird.
 
(Anmerkung: es wäre natürlich möglich das script so umzubauen, dass das admin password als argument mit übergeben wird)

z.b. ssh k3sadmin@k3s-server-1

3. 99-cleanup.sh
Das Skript dient dazu die VMs zu entfernen. Das Cloud Image bleibt dabei erhalten.
Das Cleanup entfernt die VMs, die VM Disks, Seed ISOs, DHCP Reservierungen im libvirt default Netzwerk, SSH Einträge und die erzeugten cloud-init Dateien.
Es gibt aber auch eine Option um das Image zu löschen, dazu muss das Skript mit:
REMOVE_BASE_IMAGE=1 ./99-cleanup.sh ausgeführt werden.

### Erstellen des K3s Clusters mit ansible
Wenn die VMs bereit und erstellt sind (im Durchschnitt in ca. zwei Minuten) wird das Cluster erstellt.

Es gibt eine Loadblancer VM, drei K3s Server und drei K3s worker. 
Diese werden im Ansible Inventory nach Rollen gruppiert:
- LoadBalancer
- initial Server
- weitere Server
- Agenten/Worker

Das Playbook 'ansible-playbook site.yml' baut das vollständige aber noch leere cluster auf.
Als erstes wird HAProxy auf k3s-lb-1 als LoadBalancer für die Kubernetes API eingerichtet. Danach wird k3s-server-1 mit --cluster-init als erster Server Node initialisiert. Die weiteren Server Nodes treten anschließend über den LoadBalancer (192.168.122.10:6443) dem Cluster bei. Danach werden die Agent Nodes ebenfalls über den LoadBalancer hinzugefügt.

Für den Cluster Join wird ein K3s Bootstrap Token verwendet. Dieses Token wird lokal erstellt und in der Datei .k3s-bootstrap-token gespeichert.
Das Token wird nicht in Git übernommen und ist über '.gitignore' ausgeschlossen.

Die Server werden dabei mit einem NoSchedule taint erstellt, damit sollen die workloads nur auf den Agenten laufen.

Nach der erfolgreichen Installation wird die Kubeconfig automatisch vom Cluster auf den Host kopiert und liegt im lokalen Repository vor (ebenfalls auf .gitignore). 
Die lokale IP adresse wird dabei durch die Loadbalancer IP ersetzt. 

Danach kann sie eingebunden werden:
export KUBECONFIG=k3s.yaml
source ~/.bashrc

### Installation von Fleet auf dem Cluster mit ansible

Als nächstes wird Fleet auf dem Cluster installiert.

Das Playbook 'ansible-playbook bootstrap-fleet.yml' prüft zuerst, ob die lokale Kubeconfig vorhanden ist und ob die Kubernetes API erreichbar ist. 
Danach wird Helm geprüft, weil Fleet selbst über Helm installiert wird.
Anschließend installiert das Playbook:

- Fleet CRDs
- Fleet Controller
- fleet-local Namespace
- Fleet GitRepo Resource

(gitRepo: https://github.com/ThomasTannenberg/local-kubernetes-keycloak-platform)

Früher hat dieses Playbook auch die PostgreSQL und Keycloak Secrets direkt als normale Kubernetes Secrets erzeugt.
Aber ich habe entschieden sealed secrets einzusetzen. 

Im Playbook ist dafür gesetzt:
use_plain_kubernetes_secrets: false

Für die "neue" Installation ist ein lokale Backup für den Sealed Secrets Key notwendig!

Wenn die Datei vorhanden ist, wartet das Playbook auf den Sealed Secrets Controller, spielt den alten Key wieder ein und startet den Controller neu.
Das ist wichtig, damit ein neu gebautes Cluster die vorhandenen SealedSecrets aus Git wieder entschlüsseln kann.

Wenn die Datei nicht vorhanden ist, läuft das Setup zwar weiter, aber bestehende SealedSecrets können auf einem neuem Cluster nicht entschlüsselt werden.
Dann müssen die Secrets neu erzeugt und neu mit kubeseal versiegelt werden!!! 


### GitOps mit Fleet

Als vierte Stufe übernimmt Fleet den Aufbau der Plattform Komponenten innerhalb des Clusters.
Damit ist das Repository die gewünschte 'source of truth'.
Fleet überwacht dieses Repository über eine GitRepo Resource.

Dadurch müssen die Komponenten nicht mehr manuell mit helm upgrade --install installiert werden. 
Änderungen an Chart.yaml, values.yaml oder Kubernetes Manifesten werden im Git Repository geändert, committed und gepusht. 
Fleet erkennt diese Änderungen und synchronisiert den Cluster automatisch.

Folgende Plattform Pfade sind in fleet/gitrepo.yaml eingetragen:

- platform/cert-manager
- platform/cert-manager-issuer
- platform/longhorn
- platform/postgresql
- platform/traefik
- platform/keycloak
- platform/sealed-secrets
- platform/secrets

Wichtig:
Die Liste in fleet/gitrepo.yaml ist nicht alleine die fachliche Startreihenfolge.
Die Reihenfolge wird über dependsOn gesteuert.

Die Abhängigkeiten sind aktuell so aufgebaut:

- cert-manager hat keine eigene dependsOn Abhängigkeit
- cert-manager-issuer wartet auf cert-manager
- sealed-secrets hat keine eigene dependsOn Abhängigkeit
- secrets wartet auf sealed-secrets
- longhorn wartet auf cert-manager-issuer
- traefik wartet auf cert-manager-issuer
- postgresql wartet auf longhorn und secrets
- keycloak wartet auf postgresql, traefik und secrets

Dadurch können einige Komponenten parallel starten.
Wichtig ist nur, dass die benötigten Voraussetzungen vorhanden sind, bevor die abhängigen Komponenten starten.

cert-manager muss z.b. vor dem cert-manager-issuer installiert werden, weil ClusterIssuer eine Custom Ressource vom cert-manager ist.
Sealed Secrets muss vor platform/secrets vorhanden sein, weil sonst die SealedSecret Ressourcen nicht verarbeitet werden können.
Longhorn muss vor PostgreSQL vorhanden sein, weil PostgreSQL ein persistentes Volume mit der StorageClass longhorn nutzt.
(anmerkung ich nutze Longhorn nur für PSQL)
Traefik muss vor Keycloak vorhanden sein, weil Keycloak über einen Ingress erreichbar gemacht wird.
PostgreSQL muss vor Keycloak laufen, weil Keycloak seine Datenbankverbindung zu PostgreSQL benötigt.


## Validierung des Clusters
Nach der Installation kann geprüft werden, ob das Cluster, Loadbalancer etc. funktioniert.

1. kubectl cluster-info:
2. kubectl get nodes -o wide
3. kubectl get namespaces
4. kubectl get pods -A -o wide
5. kubectl get storageclasses

# 1.3 Repository und Cluster Struktur

Ich habe versucht das Repository logisch so anzulegen, damit die einzelnen Augaben getrennt sind.

Es gibt einen Bereich für die VM Erstellung, einen Bereich für den Cluster Aufbau mit Ansible, einen Bereich für Fleet und einen Bereich für die Plattform Komponenten etc.

Die Grundstruktur sieht so aus:

local-kubernetes-keycloak-platform/
Makefile
cluster/
    libvirt/
    ansible/
docs/
fleet/
platform/
    sealed-secrets/
    secrets/
    cert-manager/
    cert-manager-issuer/
    keycloak/
    longhorn/
    postgresql/
    traefik/
.local-secrets/ *liegt auf .gitignore
tmp/ *liegt auf .gitignore

## Makefile
Makefile ist der Einstiegspunkt und macht die Installation leichter und startet die korrekten skripte.
make vm-create : erstellt die vms
make cluster-create: erstellt das k3s Cluster
make fleet-bootstrap: Installiert Fleet auf dem Cluster
make install: die vollständige Installation 
make cleanup: deinstalliert das Cluster, löscht die VMs etc.
make validate: aktueller Zustand des Cluster

## cluster/libvrit
Hier liegen die Skripte für die VM Erstellung:

00-bootstrap.sh
01-deploy-cluster-cloudimg.sh
99-cleanup.sh

## cluster/ansible:
Enthält alles für die Cluster Erstellung

inventory.ini
site.yml
bootstrap-fleet.yml
uninstall.yml
*.k3s-bootstrap-token*
*k3s.yaml*
group_vars/all.yml, secrets-example.yml, *secrets.yml*
templates/haproxy.cfg.j2


## fleet
gitrepo.yaml

Damit wird das kaufende Cluster mit dem Repostiory verbunden
Fleet überwacht dann die Platform Komponenten unter platform/

## platform/sealed-secrets
Hier liegt der Sealed Secrets Controller als Wrapper Chart.

Der Controller läuft im kube-system Namespace und entschlüsselt die SealedSecret Ressourcen wieder zu normalen Kubernetes Secrets.

Der private Schlüssel vom Controller ist dabei wichtig.
Wenn das Cluster neu gebaut wird und dieser Schlüssel nicht wiederhergestellt wird, können die alten SealedSecret Dateien nicht mehr entschlüsselt werden!

## platform/secrets
Hier liegen die verschlüsselten Secrets für PostgreSQL und Keycloak.

Die normalen Kubernetes Secrets liegen dadurch nicht als Klartext im Git Repository.
Fleet spielt nur die SealedSecret Dateien ein.
Der Sealed Secrets Controller erzeugt daraus im jeweiligen Namespace die normalen Kubernetes Secrets.

## platform/cert-manager
Der cert-manager wird benötigt, um TLS Zertifikate innerhalb des Clusters zu erzeugen und zu verwalten.

Die CRDs werden über die Helm Values aktiviert.
Prometheus ist deaktivier... hier gibt es kein Prometheus.

## platform/cert-manager-issuer
Der Issuer ist von cert-manager getrennt, da es sonst zu konflikten mit fleet gekommen ist.
Der ClusterIssuer ist eine Custom Resource. 
Ursprünglich war der ClusterIssuer ein template, aber fleet hat versucht beides gleichzeitig zu installieren. 
Aber zuerst muss cert-manager seine CRDs insallieren. 

## platform/longhorn
Dieser Ordner wird für Longhorn verwendet.
Nur PostgreSQL nutzt die StorageClass longhorn für sein pv.

## platform/traefik
Traefik läuft nur als NodePort Service. HAProxy leitet Port 80 und 443 auf die Traefik NodePorts der Agent Nodes weiter.
Dadurch ist später Keycloak über den LoadBalancer erreichbar.

## platform/postgresql

PostgreSQL läuft als Datenbank für Keycloak und nutzt ein persistentes Volume mit der StorageClass longhorn.
Die Passwörter liegen nicht als Klartext im Git Repository.
Die Secrets werden als SealedSecrets unter platform/secrets versioniert und vom Sealed Secrets Controller im Cluster wieder als Kubernetes Secrets erstellt.

## platform/keycloak
Keycloak verwendet PostgreSQL als DB. 
Der Zugriff erfolgt über Traefik Ingress und TLS über cert-manager.

## Namespaces
cattle-fleet-clusters-system
cattle-fleet-system
cert-manager
cluster-fleet-local-local-1a3d67d0a899
default
fleet-local
keycloak 
kube-node-lease
kube-public
kube-system
longhorn-system 
postgresql
traefik

Namespaces erhöhen die Übersicht, erlauben die Trennung von Secrets und Zugrifskontrollen und verbessern die Strukturen.

Bsp.:
cert-manager liegt getrennt, weil Zertifikatsverwaltung eine eigene Cluster Funktion ist.
longhorn-system liegt getrennt, weil Storage Komponenten viele eigene Controller, CSI Pods und Custom Resources mitbringen.
postgresql liegt getrennt, weil dort Datenbank Ressourcen und Datenbank Secrets liegen.
traefik liegt getrennt, weil der Ingress Controller unabhängig von den Anwendungen betrieben wird.
keycloak liegt getrennt, weil Keycloak eine eigene Anwendung ist und eigene Secrets, Ingress und TLS Ressourcen besitzt.

# 1.4 Netzwerk und Service Modell

## Netzwerk
### Loadbalancer VM / HAProxy auf k3s-lb-1 | 192.168.122.10

Da das Cluster über mehrere VMs verteilt ist wird ein LoadBalancer (HAProxy) verwendet.
Er übernimmt dabei zwei Aufgaben:

#### Kubernetes API erreichen (192.168.122.10:6443)
Dabei wird alles auf die drei K3s Server Nodes geleitet:

- 192.168.122.11:6443
- 192.168.122.12:6443
- 192.168.122.13:6443

(Anmerkung: alle anderen Nodes liegen im gleicher libvrit Netz: 192.168.122.0/24 )

Die kubeconfig zeig ebenfalls auf den Loadbalancer.

#### HTTP, HTTPS an Traefik weiterleiten

Für Anwendungen verwende in Traefik als Ingress Controller.
Ich habe mich für Traefik entschieden, da ich es auch bei der Arbeit verwende.
Dabei läuft Traefik als NodePort Service.

Die NodePorts sind:
HTTP: 30080
HTTPS: 30443

HAProxas nimm den HTTP/HTTPS Traffic auf port 80 und 443 auf und leitet ihn weiter

Client ausserhalb des Clusters --> 192.168.122.10:80 | 192.168.122.10:443 --> HAProxy --> Traefik: NodePort auf den Workern --> Ingress --> Servcie --> Pods

Es wird nur auf die Agent Nodes weitergeleitet, da nur diese für Workloads, Applicationen usw. vorgesehen sind
192.168.122.10:80 --> 192.168.122.21:30080 | 192.168.122.22:30080 | 192.168.122.23:30080
192.168.122.10:443 --> 192.168.122.21:30443 | 192.168.122.22:30443 | 192.168.122.23:30443

## Service Modell
### Cluster IP 


Durch das Service Modell ist klar getrennt, welche Komponenten nur intern erreichbar sind und welche Komponente als Einstiegspunkt für HTTP und HTTPS dient.

Die Services können mit folgendem Befehl geprüft werden:

kubectl get services -A

Alles nutzt ClusterIP und ist damit nur innerhalb des Clusters erreichbar. 

Es gibt einen festen Einstiegspunkt über den Loadbalancer: 192.168.122.10.
Interne Services bleiben intern.
Nur Traefik ist über NodePort erreichbar.
Anwendungen werden über Ingress veröffentlicht.
TLS kann über cert-manager verwaltet werden.

### Ingress
Ingress wird für Anwendungen genutzt, die von außen erreichbar sein sollen.
Hier betrifft das nur Keycloak

Prüfen mit:
kubectl get ingress -A -o wide



man kann keycloak über https://keycloak.local.example im browser erreichen

(Anmerkung: dafür habe ich einen Eintrag in /etc/hosts auf dem Host System erstellt
~cat /etc/hosts

127.0.0.1 localhost
127.0.1.1 tom-ubuntu

192.168.122.10 keycloak.local.example
.
.
.
)

Der Traffic läuft so:
Browser  --> etc/hosts --> HAProxy auf 192.168.122.10:443 --> Traefik NodePort 30443 --> Ingress keycloak.local.example --> Keycloak Service --> Keycloak Pod

## TLS
TLS wird über cert-manager vorbereitet.

Für das lokale Setup wird ein SelfSigned ClusterIssuer verwendet.
Der ClusterIssuer ist clusterweit gültig.

kubectl describe clusterissuer selfsigned-cluster-issuer

Name:         selfsigned-cluster-issuer
Namespace:    
Labels:       app.kubernetes.io/managed-by=Helm
              objectset.rio.cattle.io/hash=9f0a573d7083432f6352a1a4957564f99c76ea0b
Annotations:  meta.helm.sh/release-name: local-keycloak-platform-platform-cert-manager-issuer
              meta.helm.sh/release-namespace: cert-manager
              objectset.rio.cattle.io/id: default-local-keycloak-platform-platform-cert-manager-issuer
API Version:  cert-manager.io/v1
Kind:         ClusterIssuer
Metadata:
  Creation Timestamp:  2026-05-18T16:22:11Z
  Generation:          1
  Resource Version:    2193
  UID:                 24a2eb5e-dd0a-4d6d-8c36-2056ff6334e0
Spec:
  Self Signed:
Status:
  Conditions:
    Last Transition Time:  2026-05-18T16:22:11Z
    Observed Generation:   1
    Reason:                IsReady
    Status:                True
    Type:                  Ready
Events:                    <none>


Das ist für diese Umgebung ausreichend, weil ich hier nur einen lokalen Hostname verwenden kann. 
Let’s Encrypt kann diesen Namen nicht öffentlich validieren, solange keine öffentliche Domain und keine passende HTTP oder DNS Challenge vorhanden ist.

Für Keycloak wurde automatisch Zertifikat im Namespace keycloak erstellt.

~kubectl get certificate -n keycloak

NAME                         READY   SECRET                       AGE
keycloak.local.example-tls   True    keycloak.local.example-tls   123m


~kubectl get secret keycloak.local.example-tls -n keycloak

NAME                         TYPE                DATA   AGE
keycloak.local.example-tls   kubernetes.io/tls   3      124m

# 1.5 Storage
Wie oben beschrieben gibt es zwei StorageClasses.

~kubectl get storageclass
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  137m
longhorn               driver.longhorn.io      Retain          Immediate              true                   133m
longhorn-static        driver.longhorn.io      Delete          Immediate              true                   133m

1. Das standardmäßige 'local-path' bei k3s
2. Zusätzlich longhorn, aber nicht als default, sondern für die persistente PSQL DB

### Wieso Longhorn?
Ich möchte nicht, dass die Keycloak Daten im pod liegen um Datenverlust beim löschen oder neu erstellen des Pods verloren gehen.
Ich erstelle explizit eine StorageClass in den Helm values und ein 10Gi pvc.

primary:
  persistence:
    enabled: true
    storageClass: longhorn
    size: 10Gi

Allese Andere läuft auf local-path, was für dieses Setup ausreichen ist meiner Meinung nach.


Die Longhorn einstellungen über die values sehen so aus:

longhorn:
  persistence:
    defaultClass: false
    defaultClassReplicaCount: 2
    reclaimPolicy: Retain

  defaultSettings:
    defaultDataPath: /var/lib/longhorn
    defaultReplicaCount: 2
    storageMinimalAvailablePercentage: 25
    storageOverProvisioningPercentage: 100
    replicaSoftAntiAffinity: false
    replicaAutoBalance: best-effort
    orphanAutoDeletion: false

Drei replicas wären natürlich besser, in einer produktiv Umgebung. Aber in diesem lokal Lab halte ich zwei für ausreichend.
Retain habe ich genommen, damit PVCs nicht gelöscht werden wenn ein PVC enfernt wird. 
Kann das debugging etwas erleichtern, und da die VMs nicht dauerhaft "on" sind halte ich es für sinvoll.

### PSQL

Die Nutzung von Longhorn in PostgresSQL wird in der values definiert.

  primary:
    persistence:
      enabled: true
      storageClass: longhorn
      size: 10Gi

Keycloak selbst muss nicht Longhorn nutzen, alle Daten sind in PSQL. der Keycloak Pod selbst kann so gelöscht und neu erstellt werden, ohne dass es zu Problemen kommt. 

# 1.6 Kubernetes secrets und sensible Daten

Admin Zugangsdaten, Datenbankpasswörter und TLS Schlüssel werden nicht als Klartext in Git oder in der Dokumentation abgelegt.

Allgemein werden Secrets auf mehrere Arten erzeugt:

1. Automatisch durch Kubernetes, Helm oder die Komponenten
2. Durch cert-manager für TLS
3. Durch Sealed Secrets für PostgreSQL und Keycloak

Mit Sealed Secrets liegen die Secrets jetzt verschlüsselt im Git Repository.
Fleet kann sie deployen und der Sealed Secrets Controller erzeugt daraus die normalen Kubernetes Secrets im Cluster.

## Sealed Secrets Controller

Der Controller wird über den Pfad installiert:

platform/sealed-secrets

Er läuft im Namespace kube-system.

Dazu gibt es ein Wrapper Chart:


apiVersion: v2
name: sealed-secrets-wrapper
description: Wrapper Chart for Bitnami Sealed Secrets Controller
type: application
version: 0.1.0

dependencies:
  - name: sealed-secrets
    version: 2.17.3
    repository: https://bitnami-labs.github.io/sealed-secrets


In den values wird der Name fest gesetzt:


sealed-secrets:
  fullnameOverride: sealed-secrets-controller


Das ist wichtig, weil kubeseal später genau diesen Controller Namen und Namespace verwendet.

## Verschlüsselte Secrets

Die verschlüsselten Secret liegen hier:

platform/secrets

- keycloak-admin.sealedsecret.yaml
- keycloak-database.sealedsecret.yaml
- keycloak-postgresql-auth.sealedsecret.yaml


Diese Dateien dürfen ins Git Repository.


## Fleet Reihenfolge

Die Reihenfolge ist hier wichtig.

Sealed Secrets muss vor platform/secrets installiert werden.
PostgreSQL und Keycloak müssen warten, bis platform/secrets angewendet wurde.

Sonst kann es passieren, dass PostgreSQL oder Keycloak starten wollen, aber die benötigten Secrets noch nicht existieren.

Die Reihenfolge kommt über dependsOn.
Für die Secrets bedeutet das konkret:

1. platform/sealed-secrets
2. platform/secrets
3. platform/postgresql und platform/keycloak warten auf platform/secrets

## Wie Secrets lokal erzeugen und versiegeln

Um normale Secrets lokal zu erzeugen erzeugt und danach direkt mit kubeseal zu verschlüsseln:

Beispiel PostgreSQL:


kubectl -n postgresql create secret generic keycloak-postgresql-auth \
  --from-literal=password='KEYCLOAK_DB_PASSWORT' \
  --from-literal=postgres-password='POSTGRES_ADMIN_PASSWORT' \
  --dry-run=client -o yaml > /tmp/keycloak-postgresql-auth.secret.yaml


Keycloak Admin:


kubectl -n keycloak create secret generic keycloak-admin \
  --from-literal=admin-password='KEYCLOAK_ADMIN_PASSWORT' \
  --dry-run=client -o yaml > /tmp/keycloak-admin.secret.yaml


Keycloak DB Secret:


kubectl -n keycloak create secret generic keycloak-database \
  --from-literal=password='KEYCLOAK_DB_PASSWORT' \
  --dry-run=client -o yaml > /tmp/keycloak-database.secret.yaml


Diese Dateien bleiben nur temporär lokal.

## Daraus SealedSecrets erstellen

kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  --format yaml \
  < /tmp/keycloak-postgresql-auth.secret.yaml \
  > platform/secrets/keycloak-postgresql-auth.sealedsecret.yaml

kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  --format yaml \
  < /tmp/keycloak-admin.secret.yaml \
  > platform/secrets/keycloak-admin.sealedsecret.yaml

kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  --format yaml \
  < /tmp/keycloak-database.secret.yaml \
  > platform/secrets/keycloak-database.sealedsecret.yaml


Danach die Klartext Dateien löschen:


rm /tmp/keycloak-postgresql-auth.secret.yaml
rm /tmp/keycloak-admin.secret.yaml
rm /tmp/keycloak-database.secret.yaml


## Verwendete Secrets

Prüfung mit:


kubectl get secrets -A -o wide


### PSQL Secret

kubectl get secrets -n postgresql



NAME                               TYPE                 DATA
keycloak-postgresql-auth           Opaque               2


enthält die beiden Werte:

- postgres-password --> PSQL Admin Password
- password --> Keycloak DB User

Prüfen mit:


kubectl get secret keycloak-postgresql-auth -n postgresql
kubectl describe secret keycloak-postgresql-auth -n postgresql


Auslesen des Passwords für den Keycloak User für die PSQL-DB:


kubectl get secret keycloak-postgresql-auth -n postgresql \
  -o jsonpath="{.data.password}" | base64 -d; echo


### Keycloak Secrets


kubectl get secrets -n keycloak



NAME                             TYPE                 DATA
keycloak-admin                   Opaque               1
keycloak-database                Opaque               1
keycloak.local.example-tls       kubernetes.io/tls    3


prüfen mit z.b.:


kubectl get secret keycloak-admin -n keycloak
kubectl describe secret keycloak-admin -n keycloak


Admin Password auslesen mit:


kubectl get secret keycloak-admin -n keycloak \
  -o jsonpath="{.data.admin-password}" | base64 -d; echo


Analog mit dem keycloak-database Secret.
Dieses Secret muss doppelt vorhanden sein, einmal im Postgresql Namespace und im Keycloak Namespace, da Kubernetes Secrets nicht in unterschiedlichen namespaces funktionieren.
Bzw. es keine Zugriff außerhalb des jeweiligen Namespaces gibt.

Das TLS secret wurde durch cert-manager erstellt und enthält das zertifikat für den HTTPS key.

#### Was erstellt welches Secret

keycloak-postgresql-auth --> Sealed Secrets

keycloak-admin --> Sealed Secrets

keycloak-database --> Sealed Secrets

keycloak.local.example-tls --> cert-manager

sealed-secrets-key... --> Sealed Secrets Controller (sollte aufgehoben werden für neuinstallationen!)

Helm Secrets --> Helm

Fleet Secrets --> Fleet

Node Secrets --> K3s

## Wichtig: Sealed Secrets Key

Ein SealedSecret ist immer an den öffentlichen Schlüssel eines bestimmten Sealed Secrets Controllers gebunden.
Der passende private Schlüssel liegt im Cluster als Kubernetes Secret.

Wenn das Cluster neu aufgebaut wird und dieser private Schlüssel nicht wiederhergestellt wird, kann der neue Controller die alten SealedSecret Dateien aus Git nicht entschlüsseln.

Dann kommt z.b. folgender Fehler:


no key could decrypt secret


Das bedeutet für dieses Setup:

Wenn ich ein komplett neues Cluster baue und den alten Sealed Secrets Key nicht wieder einspiele, sind die bestehenden Dateien unter:


platform/secrets/*.sealedsecret.yaml


für dieses neue Cluster nicht mehr nutzbar.

Dann gibt es zwei Möglichkeiten.

### Möglichkeit 1: Key sichern und beim Bootstrap wieder einspielen

Das ist der bessere Weg, wenn das Git Repository dauerhaft reproduzierbar sein soll.

Ablauf:

1. Cluster wird erstellt
2. Fleet wird installiert
3. Sealed Secrets Controller wird installiert
4. alter Sealed Secrets Private Key wird eingespielt
5. Controller wird neu gestartet
6. SealedSecrets aus Git können entschlüsselt werden
7. PostgreSQL und Keycloak starten

Der Key kann lokal gesichert werden mit:


mkdir -p .local-secrets

kubectl -n kube-system get secret \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > .local-secrets/sealed-secrets-key-backup.yaml

chmod 600 .local-secrets/sealed-secrets-key-backup.yaml


Die Datei liegt bewusst unter:


.local-secrets/sealed-secrets-key-backup.yaml


Diese Datei darf nicht ins Git.
Sie ist deswegen über .gitignore ausgeschlossen.


Wiederherstellen:


kubectl apply -f .local-secrets/sealed-secrets-key-backup.yaml
kubectl -n kube-system rollout restart deployment sealed-secrets-controller


### Möglichkeit 2: Secrets neu erzeugen und neu versiegeln

Wenn der alte Key nicht mehr vorhanden ist, müssen die Secrets neu erzeugt und mit dem neuen Controller neu verschlüsselt werden.

Das bedeutet:

1. neue normale Secrets lokal erstellen
2. mit kubeseal gegen den neuen Controller verschlüsseln
3. alte SealedSecret Dateien ersetzen
4. committen und pushen
5. Fleet synced die neuen Dateien

Das ist ok für ein lokales Lab.
Für echte Umgebungen wäre das aber unschön, weil man dann die alten verschlüsselten Secrets nicht einfach wiederverwenden kann.


# 1.7 Resource Requests und Limits

Ich habe nur auf die zwei zentralen Komponenten des Setups Resource Requests und Limits gesetzt.

1. Keycloak
2. PSQL

Als relevante Anwendung und DB der Anwendung.

Resource Requests können dabei helfen dem Scheduler die besten Nodes für die Pods zu finden.
Limits begrenzen wieviel CPU und RAM maximal verwendet werden darf.

Damit kann man die Resourcen seiner Umgebung steuern, limitieren, "hungrige" Komponenten etwas in die Schranken weisen etc.

## Keycloak

resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 1500m
    memory: 2Gi

Bekommt immer mindesten 1Gi RAM und 500m CPU
Maximal aber 2Gi RAM und 1500m CPU

## PSQL

resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi

min. 512Mi RAM, 250m CPU
max. 1000m CPU, 1Gi RAM

kubectl describe pod keycloak-0 -n keycloak | grep -A8 "Limits:"
kubectl describe pod postgresql-0 -n postgresql | grep -A8 "Limits:"

# 1.8 Health Checks für Keycloak

Ich verwende drei Arten von Probes für Keycloak

## Startup

Falls der container im Pod mal wieder länger braucht als sonst, aus Gründen die nicht immer klar sind ;)

startupProbe:
    enabled: true
    initialDelaySeconds: 30
    periodSeconds: 10
    timeoutSeconds: 1
    failureThreshold: 30
    successThreshold: 1

1. Kubernetes wartet 30 Sekunden.
2. Danach wird alle 10 Sekunden geprüft.
3. Keycloak darf 30 mal "nicht bestehen"
4. Wenn er einmal "besteht" (eine Prüfung) gehts weiter mit Readiness und Liveness Prüfungen

## Readiness

Prüft ob Keycloak kommunizieren kann.

  readinessProbe:
    enabled: true
    initialDelaySeconds: 30
    periodSeconds: 10
    timeoutSeconds: 1
    failureThreshold: 3
    successThreshold: 1

Werte Beschreibung Analog zu startup Probe


## Liveness

Guckt ob der Container noch "lebt". 
Wenn diese Probe negativ ist, wird der Container neu gestartet. 

  livenessProbe:
    enabled: true
    initialDelaySeconds: 120
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 3
    successThreshold: 1

## Init container
Zusätzlich gibt es einen Init Container für PSQL

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

Damit startet Keycloak erst, wenn PostgreSQL (auf Port 5432) erreichbar ist.
Keycloak braucht direkt beim Start seine DB/Daten. 


# 2. HELM, Charts, values

Alle zentralen Plattform Komponenten werden per Helm Charts installiert. 
Im Repository liegen dafür eigene Wrapper Charts unter platform/.

Das bedeutet: Im Repository liegt nicht der komplette Chart Code der jeweiligen Anwendung vor, sondern ein kleines Chart, welches das offizielle Chart nutzt.

Beispiel Keycloak:
apiVersion: v2
name: keycloak-wrapper
description: Wrapper Chart for Keycloak
type: application
version: 0.1.0

dependencies:
  - name: keycloak
    version: 25.2.0
    repository: https://charts.bitnami.com/bitnami

Dadurch ist klar dokumentiert:

- welches Chart verwendet wird
- aus welchem Repository es kommt
- welche Version verwendet wird
- welche eigenen Values gesetzt werden

Die heruntergeladenen, gepackten charts werden per .gitignore nicht hochgeladen. 
helm dependency update --> helm dependency build erzeugt die Chart.lock und lädt die charts runter

Alle relevanten Einstellungen liegen als values.yaml vor

## 2.1 Was verwendet Helm

cert-manager | TLS Zertifikate und Certificate Ressourcen 
Sealed Secrets | Verschlüsselte Secrets für GitOps
Longhorn | Storage für persistente Daten 
PostgreSQL | Datenbank für Keycloak 
Traefik | Ingress Controller 
Keycloak | Identity und Access Management

Traefik hätte nicht per Helm installiert werden müssen, da K3s Traefik mitbringen kann. 
Aber ich habe das K3s Traefik bei der installation deaktiviert, damit die Einstellungen im Repository liegen und dort verwaltet werden können.

## 2.2 Helm Repositories

cert-manager -->	oci://quay.io/jetstack/charts	--> v1.20.2
Sealed Secrets --> https://bitnami-labs.github.io/sealed-secrets --> 2.17.3
Longhorn	--> https://charts.longhorn.io	--> 1.11.2
PostgreSQL -->	https://charts.bitnami.com/bitnami	--> 18.6.6
Traefik -->	https://traefik.github.io/charts	--> 40.2.0
Keycloak --> 	https://charts.bitnami.com/bitnami --> 	25.2.0

### Values
#### Sealed Secrets
platform/sealed-secrets/values.yaml


sealed-secrets:
  fullnameOverride: sealed-secrets-controller

Der Name ist fest gesetzt, damit kubeseal sauber gegen diesen Controller arbeiten kann.

#### cert-manager
platform/cert-manager/values.yaml

cert-manager:
  crds:
    enabled: true

  prometheus:
    enabled: false

Ich nutze kein prometheus in diesem Setup
crds sind notwendig für den Issuer

#### Longhorn
platform/longhorn/values.yaml

longhorn:
  persistence:
    defaultClass: false
    defaultClassReplicaCount: 2
    reclaimPolicy: Retain

  defaultSettings:
    defaultDataPath: /var/lib/longhorn
    defaultReplicaCount: 2
    storageMinimalAvailablePercentage: 25
    storageOverProvisioningPercentage: 100
    replicaSoftAntiAffinity: false
    replicaAutoBalance: best-effort
    orphanAutoDeletion: false

(bereits beschrieben bei Sotrage)

### PSQL
platform/postgresql/values.yaml

postgresql:
  architecture: standalone

  image:
    registry: registry-1.docker.io
    repository: bitnami/postgresql
    tag: latest

  auth:
    username: keycloak
    database: keycloak
    existingSecret: keycloak-postgresql-auth
    secretKeys:
      userPasswordKey: password
      adminPasswordKey: postgres-password

  primary:
    persistence:
      enabled: true
      storageClass: longhorn
      size: 10Gi

    resources:
      requests:
        cpu: 250m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 1Gi

(ebenfalls bereits beschrieben)

Der Image Tag steht aktuell bewusst auf latest.
Das ist für dieses lokale Lab ok, bedeutet aber auch, dass beim neuen Pull nicht zwingend exakt dieselbe PostgreSQL Image Version genutzt wird.

### Traefik
platform/traefik/values.yaml

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

  logs:
    general:
      level: INFO

(ebenfalls beschrieben)

### Keycloak
platform/keycloak/values.yaml

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

  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 1500m
      memory: 2Gi

(ebenfalls bereits beschrieben)

## Manuelle Installation

### Sealed Secrets
helm dependency update platform/sealed-secrets

helm upgrade --install sealed-secrets platform/sealed-secrets \
  --namespace kube-system \
  --create-namespace \
  --values platform/sealed-secrets/values.yaml

### Secrets

Die SealedSecret Dateien können manuell so angewendet werden:

kubectl apply -f platform/secrets/keycloak-postgresql-auth.sealedsecret.yaml
kubectl apply -f platform/secrets/keycloak-admin.sealedsecret.yaml
kubectl apply -f platform/secrets/keycloak-database.sealedsecret.yaml

Prüfen:

kubectl get sealedsecrets -A
kubectl -n postgresql get secret keycloak-postgresql-auth
kubectl -n keycloak get secret keycloak-admin
kubectl -n keycloak get secret keycloak-database

### cert-manager
helm dependency update platform/cert-manager

helm upgrade --install cert-manager platform/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --values platform/cert-manager/values.yaml

 ### Longhorn
helm dependency update platform/longhorn

helm upgrade --install longhorn platform/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --values platform/longhorn/values.yaml

### PSQL
helm dependency update platform/postgresql

helm upgrade --install postgresql platform/postgresql \
  --namespace postgresql \
  --create-namespace \
  --values platform/postgresql/values.yaml

### Traefik
helm dependency update platform/traefik

helm upgrade --install traefik platform/traefik \
  --namespace traefik \
  --create-namespace \
  --values platform/traefik/values.yaml


### Keycloak
helm dependency update platform/keycloak

helm upgrade --install keycloak platform/keycloak \
  --namespace keycloak \
  --create-namespace \
  --values platform/keycloak/values.yaml

## Reproduzierbarkeit

Die Installation ist reproduzierbar, weil folgende Dinge im Repository liegen:
1. Chart.yaml mit fester Chart Version
2. values.yaml mit Einstellungen
3. fleet.yaml mit Namespace und Abhängigkeiten
4. GitRepo Resource mit den zu synchronisierenden Pfaden

## Validierung
1. helm releases
helm list -A 

2. Fleet bundles
kubectl get bundles -n fleet-local
kubectl get bundledeployments -A

3. Pods
kubectl get pods -A
oder besser imo
watch kubectl get pods -A (und zuschauen wie alles startet)

4. Sealed Secrets
kubectl get sealedsecrets -A

5. services
kubectl get services -A -o wide

6. Ingress
kubectl get ingress -A -o wide

7. Keycloak testen
im Browser: https://keycloak.local.example


# 3. ClusterIssuer

Issuer gilt nur für einen Namespace
ClusterIssuer gilt im ganzen Cluster

Ich verwende ihn zwar nur für Keycloak, aber so kann ich das lab später leicht weiter nutzen.


# 4 Let's encrypt
Ich habe mich für die lokale Alternative C für dieses Setup entschieden.
Ich habe weder Zugang zu einem DNS Record, nocht kann ich bei einer Domain einen entsprechenden HTTP Pfad ansteuern.
Mein Zugriff über den Browser funktioniert nur wegen dem Eintrag in /etc/hosts

# 5 Wie würde es "real" funktionieren 

## HTTP-Challange
Dieses Setup habe ich in meiner prdouktiv Umgebung

Let’s Encrypt --> Domain --> Cloudflare Tunnel (cloudflared) --> Reverse Proxy --> Traefik --> cert-manager Solver


cert-manager erstellt eine Challenge Resource, einen Solver Pod, einen Service und eine Ingress Regel. 
Let’s Encrypt ruft anschließend über HTTP auf.

Damit das funktioniert, muss die öffentliche Domain von Let’s Encrypt erreichbar sein und der HTTP Traffic auf Port 80 bis zum Ingress Controller im Cluster weitergeleitet werden.
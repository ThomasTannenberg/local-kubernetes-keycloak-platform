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

Das Playbook 'ansible-playbook bootstrap-fleet.yml'  prüft zuerst, ob die lokale Kubeconfig vorhanden ist und ob die Kubernetes API erreichbar ist. 
Danach wird Helm geprüft, weil Fleet selbst über Helm installiert wird.
Anschließend installiert das Playbook:

- Fleet CRDs
- Fleet Controller
- fleet-local Namespace
- Fleet GitRepo Resource

(gitRepo: https://github.com/ThomasTannenberg/local-kubernetes-keycloak-platform)

Außerdem generiert dieses Playbook lokale Passwörter, falls noch keine Secret Datei vorhanden ist. Diese Datei liegt lokal unter:
cluster/ansible/group_vars/secrets.yml
Auch diese secrets.yml wird per .gitignore nicht in github übertragen. 
Aus dieser Datei erstellt das Playbook anschließend die benötigten Kubernetes Secrets für PostgreSQL und Keycloak.


### GitOps mit Fleet

Als vierte Stufe übernimmt Fleet den Aufbau der Plattform Komponenten innerhalb des Clusters.
Damit ist das Repository die gewünschte 'source of truth'.
Fleet überwacht dieses Repository über eine GitRepo Resource.

Dadurch müssen die Komponenten nicht mehr manuell mit helm upgrade --install installiert werden. 
Änderungen an Chart.yaml, values.yaml oder Kubernetes Manifesten werden im Git Repository geändert, committed und gepusht. 
Fleet erkennt diese Änderungen und synchronisiert den Cluster automatisch.

Folgende Plattform Pfade sind vorhanden:
- platform/cert-manager
- platform/cert-manager-issuer
- platform/longhorn
- platform/postgresql
- platform/traefik
- platform/keycloak

Die Reihenfolge wird über dependsOn gesteuert:
- cert-manager
- cert-manager-issuer
- Longhorn
- PostgreSQL
- Traefik
- Keycloak

cert-manager muss z.b. vor dem cert-manager-issuer installiert werden, weil ClusterIssuer eine Custom Ressource vom cert-manager ist.
Longhorn muss vor PostgreSQL vorhanden sein, weil PostgreSQL ein persistentes Volume mit der StorageClass longhorn nutzt.
(anmerkung ich nutze Longhorn nur für PSQL)
Traefik muss vor Keycloak vorhanden sein, weil Keycloak über einen Ingress erreichbar gemacht wird.
PostgreSQL muss vor Keycloak laufen, weil Keycloak seine Datenbankverbindung zu PostgreSQL benötigt.


## Validierung des Clusters
Nach der Installation kann geprüft werden, ob das Cluster, Loadbalancer etc. funktioniert.

1. kubectl cluster-info:
Kubernetes control plane is running at https://192.168.122.10:6443
CoreDNS is running at https://192.168.122.10:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://192.168.122.10:6443/api/v1/namespaces/kube-system/services/https:metrics-server:https/proxy



2. kubectl get nodes -o wide
NAME           STATUS   ROLES                AGE   VERSION        INTERNAL-IP      EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION       CONTAINER-RUNTIME
k3s-agent-1    Ready    worker               32m   v1.35.4+k3s1   192.168.122.21   <none>        Ubuntu 22.04.5 LTS   5.15.0-173-generic   containerd://2.2.3-k3s1
k3s-agent-2    Ready    worker               32m   v1.35.4+k3s1   192.168.122.22   <none>        Ubuntu 22.04.5 LTS   5.15.0-173-generic   containerd://2.2.3-k3s1
k3s-agent-3    Ready    worker               32m   v1.35.4+k3s1   192.168.122.23   <none>        Ubuntu 22.04.5 LTS   5.15.0-173-generic   containerd://2.2.3-k3s1
k3s-server-1   Ready    control-plane,etcd   33m   v1.35.4+k3s1   192.168.122.11   <none>        Ubuntu 22.04.5 LTS   5.15.0-173-generic   containerd://2.2.3-k3s1
k3s-server-2   Ready    control-plane,etcd   33m   v1.35.4+k3s1   192.168.122.12   <none>        Ubuntu 22.04.5 LTS   5.15.0-173-generic   containerd://2.2.3-k3s1
k3s-server-3   Ready    control-plane,etcd   32m   v1.35.4+k3s1   192.168.122.13   <none>        Ubuntu 22.04.5 LTS   5.15.0-173-generic   containerd://2.2.3-k3s1


3. kubectl get namespaces
NAME                                     STATUS   AGE
cattle-fleet-clusters-system             Active   34m
cattle-fleet-system                      Active   35m
cert-manager                             Active   34m
cluster-fleet-local-local-1a3d67d0a899   Active   34m
default                                  Active   36m
fleet-local                              Active   34m
keycloak                                 Active   34m
kube-node-lease                          Active   36m
kube-public                              Active   36m
kube-system                              Active   36m
longhorn-system                          Active   33m
postgresql                               Active   34m
traefik                                  Active   33m



4. kubectl get pods -A -o wide
NAMESPACE             NAME                                                READY   STATUS    RESTARTS      AGE   IP           NODE           NOMINATED NODE   READINESS GATES
cattle-fleet-system   fleet-agent-84f94fd469-qb4rq                        1/1     Running   0             35m   10.42.4.6    k3s-agent-2    <none>           <none>
cattle-fleet-system   fleet-controller-775d68bbbf-z52rj                   3/3     Running   0             35m   10.42.7.2    k3s-agent-1    <none>           <none>
cattle-fleet-system   gitjob-5ddc58fdd5-8dzr6                             1/1     Running   0             35m   10.42.4.2    k3s-agent-2    <none>           <none>
cattle-fleet-system   helmops-66cc9b955c-zfgvn                            1/1     Running   0             35m   10.42.5.2    k3s-agent-3    <none>           <none>
cert-manager          cert-manager-65b765f58f-h58xb                       1/1     Running   0             34m   10.42.5.7    k3s-agent-3    <none>           <none>
cert-manager          cert-manager-cainjector-679cdbbb5c-jfwmn            1/1     Running   0             34m   10.42.5.6    k3s-agent-3    <none>           <none>
cert-manager          cert-manager-webhook-75bbd7d54f-q9mvs               1/1     Running   0             34m   10.42.4.7    k3s-agent-2    <none>           <none>
keycloak              keycloak-0                                          1/1     Running   0             32m   10.42.4.19   k3s-agent-2    <none>           <none>
kube-system           coredns-c4dbffb5f-pzd8l                             1/1     Running   0             37m   10.42.0.4    k3s-server-1   <none>           <none>
kube-system           local-path-provisioner-5c4dc5d66d-864l6             1/1     Running   0             37m   10.42.0.2    k3s-server-1   <none>           <none>
kube-system           metrics-server-786d997795-rwtqk                     1/1     Running   0             37m   10.42.0.3    k3s-server-1   <none>           <none>
longhorn-system       csi-attacher-5557d89ccf-8qr4w                       1/1     Running   0             33m   10.42.4.14   k3s-agent-2    <none>           <none>
longhorn-system       csi-attacher-5557d89ccf-d8b8m                       1/1     Running   0             33m   10.42.7.9    k3s-agent-1    <none>           <none>
longhorn-system       csi-attacher-5557d89ccf-ljkct                       1/1     Running   0             33m   10.42.5.14   k3s-agent-3    <none>           <none>
longhorn-system       csi-provisioner-857485dbfb-5jbb2                    1/1     Running   0             33m   10.42.7.10   k3s-agent-1    <none>           <none>
longhorn-system       csi-provisioner-857485dbfb-ndqq2                    1/1     Running   0             33m   10.42.4.15   k3s-agent-2    <none>           <none>
longhorn-system       csi-provisioner-857485dbfb-rr7w8                    1/1     Running   0             33m   10.42.5.15   k3s-agent-3    <none>           <none>
longhorn-system       csi-resizer-64dcb47b78-58w87                        1/1     Running   0             33m   10.42.5.13   k3s-agent-3    <none>           <none>
longhorn-system       csi-resizer-64dcb47b78-qr69c                        1/1     Running   0             33m   10.42.7.11   k3s-agent-1    <none>           <none>
longhorn-system       csi-resizer-64dcb47b78-s5bvr                        1/1     Running   0             33m   10.42.4.16   k3s-agent-2    <none>           <none>
longhorn-system       csi-snapshotter-9dc596c7c-vdzlz                     1/1     Running   0             32m   10.42.4.17   k3s-agent-2    <none>           <none>
longhorn-system       csi-snapshotter-9dc596c7c-z5mn4                     1/1     Running   0             32m   10.42.5.16   k3s-agent-3    <none>           <none>
longhorn-system       csi-snapshotter-9dc596c7c-zsdwx                     1/1     Running   0             32m   10.42.7.13   k3s-agent-1    <none>           <none>
longhorn-system       engine-image-ei-c9fa6d45-4strb                      1/1     Running   0             33m   10.42.4.12   k3s-agent-2    <none>           <none>
longhorn-system       engine-image-ei-c9fa6d45-5zdxc                      1/1     Running   0             33m   10.42.5.11   k3s-agent-3    <none>           <none>
longhorn-system       engine-image-ei-c9fa6d45-j7kdh                      1/1     Running   0             33m   10.42.7.5    k3s-agent-1    <none>           <none>
longhorn-system       instance-manager-4b471b7c06492de82ed1fa005d31db27   1/1     Running   0             33m   10.42.7.6    k3s-agent-1    <none>           <none>
longhorn-system       instance-manager-e0153fa1d335aa41faa0c28cf653109a   1/1     Running   0             33m   10.42.4.13   k3s-agent-2    <none>           <none>
longhorn-system       instance-manager-eae13c6e1aed9de84ba16bac3f5ec1eb   1/1     Running   0             33m   10.42.5.12   k3s-agent-3    <none>           <none>
longhorn-system       longhorn-csi-plugin-cncfj                           3/3     Running   0             32m   10.42.5.17   k3s-agent-3    <none>           <none>
longhorn-system       longhorn-csi-plugin-hz4zq                           3/3     Running   0             32m   10.42.7.12   k3s-agent-1    <none>           <none>
longhorn-system       longhorn-csi-plugin-mdz8n                           3/3     Running   0             32m   10.42.4.18   k3s-agent-2    <none>           <none>
longhorn-system       longhorn-driver-deployer-7f5b6fb9b8-xsds6           1/1     Running   0             33m   10.42.5.8    k3s-agent-3    <none>           <none>
longhorn-system       longhorn-manager-ccvqb                              2/2     Running   0             33m   10.42.4.9    k3s-agent-2    <none>           <none>
longhorn-system       longhorn-manager-dvhds                              2/2     Running   1 (33m ago)   33m   10.42.5.9    k3s-agent-3    <none>           <none>
longhorn-system       longhorn-manager-nn4qd                              2/2     Running   0             33m   10.42.7.3    k3s-agent-1    <none>           <none>
longhorn-system       longhorn-ui-7fb5c57b8b-n4cmv                        1/1     Running   0             33m   10.42.7.4    k3s-agent-1    <none>           <none>
longhorn-system       longhorn-ui-7fb5c57b8b-q58v4                        1/1     Running   0             33m   10.42.4.10   k3s-agent-2    <none>           <none>
postgresql            postgresql-0                                        1/1     Running   0             33m   10.42.7.14   k3s-agent-1    <none>           <none>
traefik               traefik-775f4fffdc-7tksv                            1/1     Running   0             33m   10.42.5.10   k3s-agent-3    <none>           <none>
traefik               traefik-775f4fffdc-9ddls                            1/1     Running   0             33m   10.42.4.11   k3s-agent-2    <none>           <none>



5. kubectl get storageclasses

NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  37m
longhorn               driver.longhorn.io      Retain          Immediate              true                   34m
longhorn-static        driver.longhorn.io      Delete          Immediate              true                   34m

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
    cert-manager/
    cert-manager-issuer/
    keycloak/
    longhorn/
    postgresql/
    traefik/
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

## platform/cert-manager
Der cert-manager wird benötigt, um TLS Zertifikate innerhalb des Clusters zu erzeugen und zu verwalten.

Die CRDs werden über die Helm Values aktiviert.
Prometheus deaktiviert... hier gibt es kein Prometheus.

## platform/cert-manager-issuer
Der Issuer ist von cert-manager getrennt, da es sonst zu konflikten mit fleet gekommen ist.
Der VlusterIssuer ist eine Custom Resource. 
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

Die Passwörter liegen nicht im Git Repository, sondern werden beim Fleet Bootstrap lokal generiert und als Kubernetes Secrets erstellt.

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

Für Anwendungenr verwende in Traefik als Ingress Controller.
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
NAMESPACE             NAME                          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
cattle-fleet-system   gitjob                        ClusterIP   10.43.3.94      <none>        80/TCP                       110m
cattle-fleet-system   monitoring-fleet-controller   ClusterIP   10.43.117.255   <none>        8080/TCP                     110m
cattle-fleet-system   monitoring-gitjob             ClusterIP   10.43.249.52    <none>        8081/TCP                     110m
cert-manager          cert-manager-webhook          ClusterIP   10.43.158.27    <none>        443/TCP                      109m
default               kubernetes                    ClusterIP   10.43.0.1       <none>        443/TCP                      111m
keycloak              keycloak                      ClusterIP   10.43.83.138    <none>        80/TCP                       106m
keycloak              keycloak-headless             ClusterIP   None            <none>        8080/TCP                     106m
kube-system           kube-dns                      ClusterIP   10.43.0.10      <none>        53/UDP,53/TCP,9153/TCP       111m
kube-system           metrics-server                ClusterIP   10.43.177.120   <none>        443/TCP                      111m
longhorn-system       longhorn-admission-webhook    ClusterIP   10.43.110.101   <none>        9502/TCP                     108m
longhorn-system       longhorn-backend              ClusterIP   10.43.18.71     <none>        9500/TCP                     108m
longhorn-system       longhorn-frontend             ClusterIP   10.43.151.124   <none>        80/TCP                       108m
longhorn-system       longhorn-recovery-backend     ClusterIP   10.43.2.113     <none>        9503/TCP                     108m
postgresql            postgresql                    ClusterIP   10.43.96.1      <none>        5432/TCP                     108m
postgresql            postgresql-hl                 ClusterIP   None            <none>        5432/TCP                     108m
traefik               traefik                       NodePort    10.43.190.216   <none>        80:30080/TCP,443:30443/TCP   108m

Alles (bis auf Traefik, siehe oben in der Dokumentation) nutzt ClusterIP und ist damit nur innerhalb des Clusters erreichbar. 

Es gibt einen festen Einstiegspunkt über den Loadbalancer: 192.168.122.10.
Interne Services bleiben intern.
Nur Traefik ist über NodePort erreichbar.
Anwendungen werden über Ingress veröffentlicht.
TLS kann über cert-manager verwaltet werden.

### Ingress
Ingress wird für Anwendungen genutzt, die von außen erreichbar sein sollen.
Hier betrifft das nur Keycloak

kubectl get ingress -A -o wide

NAMESPACE   NAME       CLASS     HOSTS                    ADDRESS   PORTS     AGE
keycloak    keycloak   traefik   keycloak.local.example             80, 443   110m

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


Admin Zugangsdaten, Datenbankpasswörter und TLS Schlüssel werden nicht in Git oder in der Dokumentation abgelegt.

Allgemein werden Secrets auf zwei Arten erzeugt:

1. Automatisch durch Kubernetes, Helm oder die Komponenten
2. Durch das Ansible Playbook bootstrap-fleet.yml für PostgreSQL und Keycloak

Die lokal, zur runtime erzeugten Passwörter liegen nur in der lokalen Datei:

cluster/ansible/group_vars/secrets.yml
Diese Datei wird über .gitignore ausgeschlossen und nicht hochgeladen.

## Verwendete Secrets

Prüfung mit kubectl get secrets -A -o wide

### PSQL Secret


kubectl get secrets -n postgresql 

NAME                               TYPE                 DATA   AGE
keycloak-postgresql-auth           Opaque               2      24h


enthält die beiden Werte:
- postgres-password --> PSQL Admin Password
- password --> Keycloak DB User

Prüfen mit:
- kubectl get secret keycloak-postgresql-auth -n postgresql
- kubectl describe secret keycloak-postgresql-auth -n postgresql

Auslesen des Passwords für den Keycloak User für die PSQL-DB:

kubectl get secret keycloak-postgresql-auth -n postgresql \
  -o jsonpath="{.data.password}" | base64 -d; echo

### Keycloak Secrets

kubectl get secrets -n keycloak

NAME                             TYPE                 DATA   AGE
keycloak-admin                   Opaque               1      24h
keycloak-database                Opaque               1      24h
keycloak.local.example-tls       kubernetes.io/tls    3      24h

prüfen mit (z.b.):
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

keycloak-postgresql-auth --> Ansible 

keycloak-admin --> Ansible

keycloak-database --> Ansible

keycloak.local.example-tls --> cert-manager

Helm Secrets --> Helm

Fleet Secrets --> Fleet

Node Secrets --> K3s

##### Anmerkung
Für dieses Setup ist das ausschließen der Secrets nach dem erzeugen ausreichend.
In meiner Produktiv Umgebung nutze ich dazu Sealed Secrets. 
Damit liegen die Secrets zwar in Git, aber dort verschlüsselt, und sie werden anschließen im Cluster entschlüsselt.

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
Longhorn | Storage für persistente Daten 
PostgreSQL | Datenbank für Keycloak 
Traefik | Ingress Controller 
Keycloak | Identity und Access Management

Traefik hätte nicht per Helm installiert werden müssen, da K3s Traefik mitbringen kann. 
Aber ich habe das K3s Traefik bei der installation deaktiviert, damit die Einstellungen im Repository liegen und dort verwaltet werden können.

## 2.2 Helm Repositories

cert-manager -->	oci://quay.io/jetstack/charts	--> v1.20.2
Longhorn	--> https://charts.longhorn.io	--> 1.11.2
PostgreSQL -->	https://charts.bitnami.com/bitnami	--> 18.6.6
Traefik -->	https://traefik.github.io/charts	--> 40.2.0
Keycloak --> 	https://charts.bitnami.com/bitnami --> 	25.2.0

### Values
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

4. services
kubectl get services -A -o wide

5. Ingress
kubectl get ingress -A -o wide

6. Keycloak testen
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
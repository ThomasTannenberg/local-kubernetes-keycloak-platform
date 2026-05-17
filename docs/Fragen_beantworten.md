# 1.1 Frage: Wahl der Kubernetes-Distribution

Ich habe mich für ein K3s Multi Node Setup entschieden, welches lokal auf meinem System läuft.

In der Vergangenheit habe ich ich private Setups zum lernen und testen mit minikube aufgebaut. Minikube würde, genauso wie das neue K3s Setup, die Anforderungen erfüllen. 
Aber für diese Aufgabe wollte ich ein Setup erstellen, welches möglichst nahe an einer produktiv Umgebung ist.

Das gesamte Setup ist "overkill" für die Aufgabe, aber da ich noch nie ein K3s Cluster aufgebaut habe, sah ich es als gute Möglichkeit zum lernen.

Trotzdem ist K3s relativ schlank und kann auf lokalen virtuellen Maschinen betrieben werden. 

Vorteile dieser Lösung:

- Das Multi Node Setup bildet reale Kubernetes Konzepte besser ab als ein reines Single Node Cluster.
- Server Nodes und Worker Nodes können getrennt betrachtet werden.
- Ingress, Storage, Services, StatefulSets und cert-manager können realistisch getestet werden.
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

Das Cluster muss wird in zwei Hauptstufen erstellt.

### Erstellen der VMs
Dafür werden mit scripts virtuelle Maschinen auf KVM/libvrit Basis erstellt. Als Image verwende ich ein Ubuntu Cloud Image.
Die VMs erhalten feste IP Adressen, feste MAC Adressen und eine definierte Ressourcenzuweisung für RAM, vCPU und Disk. 
Dadurch ist das Setup reproduzierbar und kann nach einem Cleanup erneut mit derselben Struktur aufgebaut werden.

Es werden 7 Server erstellt:

|Server| IP | MAC | RAM | vCPU | Festplatte

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
Zusätzlich werden SSH Aliase erstellt damit die VMs direkt über Namen, anstatt nur IPs erreicht werden können

z.b. ssh k3sadmin@k3s-server-1

3. 99-cleanup.sh
Das Skript dient dazu die VMs zu entfernen. Das Cloud Image bleibt dabei erhalten.
Das Cleanup entfernt die VMs, die VM Disks, Seed ISOs, DHCP Reservierungen im libvirt default Netzwerk, SSH Einträge und die erzeugten cloud-init Dateien.
Es gibt aber auch eine Option um das Image zu löschen, dazu muss das Skript mit:
REMOVE_BASE_IMAGE=1 ./99-cleanup.sh ausgeführt werden.

### Erstellen des K3s Clusters
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

Das Token ist sicherheitsrelevant, weil damit neue Nodes dem Cluster beitreten können. Deshalb wird es nur lokal gespeichert, nicht dokumentiert und nicht in Git abgelegt.

Nach der erfolgreichen Installation wird die Kubeconfig automatisch vom Cluster auf den Host kopiert und liegt im lokalen Repository vor (ebenfalls auf .gitignore). 
Die lokale IP adresse wird dabei durch die Loadbalancer IP ersetzt. 

Danach kann sie eingebunden werden:
export KUBECONFIG=k3s.yaml
source ~/.bashrc

## Validierung des Cluster Zugriffs
Nach der Installation kann geprüft werden, ob der Kubernetes Kontext korrekt eingerichtet ist und der Zugriff über den LoadBalancer funktioniert.

1. kubectl cluster-info:

Kubernetes control plane is running at https://192.168.122.10:6443
CoreDNS is running at https://192.168.122.10:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://192.168.122.10:6443/api/v1/namespaces/kube-system/services/https:metrics-server:https/proxy

2. kubectl get nodes -o wide
NAME           STATUS   ROLES                AGE   VERSION        INTERNAL-IP      EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION       CONTAINER-RUNTIME
k3s-agent-1    Ready    worker               19h   v1.35.4+k3s1   192.168.122.21   <none>        Ubuntu 22.04.5 LTS   5.15.0-173-generic   containerd://2.2.3-k3s1
k3s-agent-2    Ready    worker               19h   v1.35.4+k3s1   192.168.122.22   <none>        Ubuntu 22.04.5 LTS   5.15.0-173-generic   containerd://2.2.3-k3s1
k3s-agent-3    Ready    worker               19h   v1.35.4+k3s1   192.168.122.23   <none>        Ubuntu 22.04.5 LTS   5.15.0-173-generic   containerd://2.2.3-k3s1
k3s-server-1   Ready    control-plane,etcd   19h   v1.35.4+k3s1   192.168.122.11   <none>        Ubuntu 22.04.5 LTS   5.15.0-173-generic   containerd://2.2.3-k3s1
k3s-server-2   Ready    control-plane,etcd   19h   v1.35.4+k3s1   192.168.122.12   <none>        Ubuntu 22.04.5 LTS   5.15.0-173-generic   containerd://2.2.3-k3s1
k3s-server-3   Ready    control-plane,etcd   19h   v1.35.4+k3s1   192.168.122.13   <none>        Ubuntu 22.04.5 LTS   5.15.0-173-generic   containerd://2.2.3-k3s1

3. kubectl get namespaces
NAME              STATUS   AGE
default           Active   19h
kube-node-lease   Active   19h
kube-public       Active   19h
kube-system       Active   19h

4. kubectl get pods -A
NAMESPACE     NAME                                      READY   STATUS    RESTARTS      AGE
kube-system   coredns-c4dbffb5f-v42st                   1/1     Running   2 (85m ago)   19h
kube-system   local-path-provisioner-5c4dc5d66d-jlhcn   1/1     Running   2 (85m ago)   19h
kube-system   metrics-server-786d997795-8sh26           1/1     Running   2 (85m ago)   19h

Die Control Planes sind über dne HAProxy LoadBalancer erreichbar.
Alle sechs Nodes sind 'READY' und die Rollenzuweisungen sind korrekt gesetzt.
CoreDNS stellt die interne DNS Auflösung des Clusters bereit.

Die Namespaces für Ingress, cert-manager und Keycloak werden später durch die Installationsschritte der jeweiligen Komponenten erstellt.
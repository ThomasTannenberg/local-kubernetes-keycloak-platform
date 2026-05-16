# Local Kubernetes Keycloak Platform

Dieses Repository enthält ein lokales Kubernetes Setup.


## Ziel

Ziel ist ein reproduzierbares lokales Kubernetes Setup mit:

- K3s Cluster
- HAProxy LoadBalancer für die Kubernetes API
- Traefik als Ingress Controller
- cert-manager für TLS Zertifikate
- Longhorn als Storage Lösung
- PostgreSQL als Datenbank
- Keycloak per Helm
- HTTPS Zugriff auf Keycloak
- Validierung und Cleanup

## Architektur

Die lokale Umgebung besteht aus sieben VMs:

| Host | IP | Rolle |
|---|---:|---|
| k3s-lb-1 | 192.168.122.10 | HAProxy LoadBalancer |
| k3s-server-1 | 192.168.122.11 | Control Plane und etcd |
| k3s-server-2 | 192.168.122.12 | Control Plane und etcd |
| k3s-server-3 | 192.168.122.13 | Control Plane und etcd |
| k3s-agent-1 | 192.168.122.21 | Worker |
| k3s-agent-2 | 192.168.122.22 | Worker |
| k3s-agent-3 | 192.168.122.23 | Worker |

### Arichtektur anpassen:
1. /cluster/libvrit/01-deploy-cluster-dloudimg.sh anpassen:

Die VM-Liste steht oben im Deploy Skript im Array `VMS`. Format:
`name|ip|mac|memory_mb|vcpus|disk_gb`. 
Eine VM hinzufügen heißt: eine
Zeile ergänzen, analog entfernen. Auch andere Parameter können so angepasst werden.

2. /cluster/ansible/inventory.ini
anpassen

## Voraussetzungen

Benötigte Tools auf dem Hostsystem:

```bash
ansible --version
kubectl version --client
helm version
virsh --version
virt-install --version
make  --version
kubectl --version
helm version


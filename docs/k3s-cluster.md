# k3s-Cluster mit Ansible aufsetzen

Automatisiert den gesamten Cluster-Aufbau auf den 7 VMs aus dem
VM-Bootstrap (`k3s-lb-1`, `k3s-server-{1,2,3}`, `k3s-agent-{1,2,3}`):

1. HAProxy als TCP-Load-Balancer auf `k3s-lb-1`
2. `k3s-server-1` mit `--cluster-init` (etcd-Bootstrap, Traefik disabled)
3. `k3s-server-2/-3` joinen via Load-Balancer (sequentiell)
4. Drei Agents joinen via Load-Balancer (parallel)
5. Server-Nodes bekommen `NoSchedule`-Taint direkt beim Install
6. Agents bekommen `node-role.kubernetes.io/worker=true`-Label direkt beim Install
7. Kubeconfig wird automatisch nach `./k3s.yaml` gefetcht, `127.0.0.1` wird zur LB-IP

## Voraussetzungen

VMs laufen, du erreichst sie per SSH-Alias (`ssh k3s-lb-1` etc.). Ansible
auf dem Host installieren:

```bash
sudo apt update
sudo apt install -y ansible
```

## Ablauf

```bash
# 1. Konnektivität testen
ansible -m ping all


# 2. Cluster aufsetzen 
# trocken testen mit ansible-playbook --check site.yml
ansible-playbook site.yml

# 4. Kubeconfig nutzen
export KUBECONFIG="$PWD/k3s.yaml"
kubectl get nodes -o wide
```

## Cluster neu aufsetzen

```bash
ansible-playbook uninstall.yml
ansible-playbook site.yml
```

`uninstall.yml` ruft die offiziellen `k3s-uninstall.sh` / `k3s-agent-uninstall.sh`
Skripte auf, die k3s sauber zurückrollen. Die VMs selbst bleiben unangetastet.

## Dateien

| Datei                   | Zweck                                                |
|-------------------------|------------------------------------------------------|
| `ansible.cfg`           | Default-Inventory, kein Host-Key-Checking            |
| `inventory.ini`         | Hosts, gruppiert nach Rolle (`lb`/`init`/`servers`/`agents`) |
| `group_vars/all.yml`    | LB-IP, Token-Lookup, Traefik/Taint-Toggles           |
| `templates/haproxy.cfg.j2` | HAProxy-Config, Backends aus Inventory generiert |
| `site.yml`              | Hauptplaybook, 7 Plays                                |
| `uninstall.yml`         | Cluster zurückrollen                                  |




**Traefik per `--disable traefik`** abgeschaltet. Wir später manuel per HELM install aufgesetzt.

**HAProxy-Backends aus dem Inventory generiert** Anzahl der Server wird aus dem Inventory generiert.
So kann man anpasswenn man vorher Server anderes erstellt hat.

**Sequentielles Joinen der Server (`serial: 1`)** ist bei etcd
zwingend, sonst kommt es zu Races und Fehlern. Agents joinen parallel.

- Bitte `helm` und `kubectl` lokal auf dem Host installieren
- Eigenen Traefik per Helm installieren

## Token-Handhabung

Der Token wird zur Runtime erzeugt uns muss später manuel aus dem Cluster gelesen werden.
Sollte man ihn brauchen



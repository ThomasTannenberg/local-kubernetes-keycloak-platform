# k3s-Infrastruktur-Automatisierung

Automatisierung eines Cluster-Aufbaus auf Ubuntu 26.04 Host
mit KVM/libvirt und Ubuntu-22.04-Cloud-Image.

## Was wird angelegt

| Name           | IP              | MAC                | RAM   | vCPU | Disk |
|----------------|-----------------|--------------------|-------|------|------|
| k3s-lb-1       | 192.168.122.10  | 52:54:00:00:00:10  | 2 GB  | 1    | 20 G |
| k3s-server-1   | 192.168.122.11  | 52:54:00:00:00:11  | 6 GB  | 2    | 40 G |
| k3s-server-2   | 192.168.122.12  | 52:54:00:00:00:12  | 6 GB  | 2    | 40 G |
| k3s-server-3   | 192.168.122.13  | 52:54:00:00:00:13  | 6 GB  | 2    | 40 G |
| k3s-agent-1    | 192.168.122.21  | 52:54:00:00:00:21  | 10 GB | 2    | 60 G |
| k3s-agent-2    | 192.168.122.22  | 52:54:00:00:00:22  | 10 GB | 2    | 60 G |
| k3s-agent-3    | 192.168.122.23  | 52:54:00:00:00:23  | 10 GB | 2    | 60 G |

Summe: **50 GB RAM, 13 vCPUs, 320 GB Disk**.

Anmerkung: Das ist sehr viel und für die Aufgabe overkill. 
50GB RAM ist aufgrund der Lage derzeit kaum zu erwarten. 
Mein System ist älter und damals war RAM noch nicht so teuer! 

## Konfiguration anpassen

Die VM-Liste steht oben im Deploy-Skript im Array `VMS`. Format:
`name|ip|mac|memory_mb|vcpus|disk_gb`. 

User-Name (`k3sadmin`) ist in `SSH_USER` oben gepflegt.

Anzahl der Server, IP, MAC RAM vCPU und Disk kann im 01-deploy-cluster-cloudimg.sh angepasst werden:
Auszug aus dem skript:

VMS=(
  "k3s-lb-1|192.168.122.10|52:54:00:00:00:10|2048|1|20"
  "k3s-server-1|192.168.122.11|52:54:00:00:00:11|6144|2|40"
  "k3s-server-2|192.168.122.12|52:54:00:00:00:12|6144|2|40"
  "k3s-server-3|192.168.122.13|52:54:00:00:00:13|6144|2|40"
  "k3s-agent-1|192.168.122.21|52:54:00:00:00:21|10240|2|60"
  "k3s-agent-2|192.168.122.22|52:54:00:00:00:22|10240|2|60"
  "k3s-agent-3|192.168.122.23|52:54:00:00:00:23|10240|2|60"
)


## Ablauf

```bash
# 1. Pakete + Gruppen einrichten (einmalig ausführen. Danach nicht mehr notwendig!)
./00-bootstrap.sh

# 2. REBOOT, damit libvirt/kvm-Gruppen aktiv werden. 
# Kann optional sein...


# 3 Komplettes Cluster anlegen (
./01-deploy-cluster-cloudimg.sh

# 4. Login testen
ssh k3s-lb-1
ssh k3s-server-1
```

Das Skript lädt das Ubuntu Cloud Image (~600 MB) beim ersten Lauf
automatisch nach `~/Downloads/`. 

Wenn etwas schiefgeht, oder die VMs gelöscht werden sollen

```bash
./99-cleanup.sh                          # behält das Cloud-Image-Base
REMOVE_BASE_IMAGE=1 ./99-cleanup.sh      # löscht auch das Base-Image
```

## Skript-Übersicht

| Skript                              | Zweck                                            |
|-------------------------------------|--------------------------------------------------|
| `00-bootstrap.sh`                   | Pakete, Gruppen, SSH-Key, Verzeichnisse          |
| `01-deploy-cluster-cloudimg.sh`     | Alle 7 VMs aus Cloud-Image anlegen               |
| `99-cleanup.sh`                     | Komplettes Cluster wieder abreißen               |

## Warum Cloud-Image statt Installer-ISO

- **schneller**: 2 min pro VM statt 10-20 min Autoinstall. Es macht den gesamten Prozess deutlich angenehmer. 
- **Kleinerer Download**: ca. 600 MB Cloud-Image statt 2 GB Installer-ISO
- **Backing-File-Klon**: alle 7 VMs teilen sich initial das Base-Image, spart Speicher und ist meiner Meinung nach für ein "Lab" Setup okay.


## SSH-Key

Das Bootstrap-Skript prüft `~/.ssh/id_ed25519`:

- **Existiert** → wird verwendet
- **Existiert nicht** → wird ohne Passphrase neu erzeugt

**Falls dein Key eine Passphrase hat**, das Deploy-Skript SSH-pollt im
BatchMode und kann die nicht abfragen. Drei Wege:

1. `ssh-agent` füttern: `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519`
2. Separaten Lab-Key ohne Passphrase erzeugen und im Skript oben
   `SSH_KEY_PUB`/`SSH_KEY_PRIV` auf den neuen Pfad setzen
3. (Nicht empfohlen) Passphrase vom bestehenden Key entfernen



## Verzeichnisse

```
/var/lib/libvirt/images/    # VM-Disks (root)
/var/lib/libvirt/boot/      # Cloud-Image-Base + Seed-ISOs (root)
~/Development/cloud-init/   # cloud-init Quelldateien pro VM (user)
~/Downloads/                # Cloud-Image-Cache (user)
~/.ssh/config               # SSH-Aliase
```

## Cleanup-Verhalten

`./99-cleanup.sh` entfernt:

- Alle VMs (destroy + undefine + Disks)
- Seed-ISOs unter `/var/lib/libvirt/boot/<name>-seed.iso`
- DHCP-Reservations im libvirt-`default`-Netz
- `~/.ssh/config`-Block und `known_hosts`-Einträge
- cloud-init-Quelldateien unter `~/Development/cloud-init/`

**Nicht entfernt** wird das heruntergeladene Cloud-Image-Base
(`/var/lib/libvirt/boot/jammy-server-cloudimg-amd64.img`), damit
Re-Runs schneller gehen. 

Trotzdem entfernen mit:

```bash
REMOVE_BASE_IMAGE=1 ./99-cleanup.sh
```



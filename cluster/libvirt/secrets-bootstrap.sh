#!/usr/bin/env bash
#
# secrets-bootstrap.sh
#
# Einmaliger Bootstrap der SealedSecrets nach dem ersten Cluster-Start.
#
# Ablauf:
#   1. Wartet, bis der sealed-secrets-controller bereit ist
#   2. Erzeugt frische Zufallspasswörter
#   3. Versiegelt sie mit kubeseal gegen den laufenden Controller
#   4. Schreibt die SealedSecret YAMLs nach platform/secrets/
#      (überschreibt vorhandene Dateien aus dem Git Repository)
#   5. Wendet die SealedSecrets direkt auf das Cluster an
#   6. Sichert den Private Key des Controllers lokal in .local-secrets/
#
# Benötigt wird:
#   kubectl, kubeseal, openssl
#
# Aufruf:
#   make secrets-bootstrap
#   oder direkt:
#   KUBECONFIG=cluster/ansible/k3s.yaml ./scripts/secrets-bootstrap.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

KUBECONFIG="${KUBECONFIG:-${REPO_ROOT}/cluster/ansible/k3s.yaml}"
export KUBECONFIG

SECRETS_DIR="${REPO_ROOT}/platform/secrets"
KEY_BACKUP_DIR="${REPO_ROOT}/.local-secrets"
KEY_BACKUP_FILE="${KEY_BACKUP_DIR}/sealed-secrets-key-backup.yaml"
CONTROLLER_NAMESPACE="kube-system"
CONTROLLER_NAME="sealed-secrets-controller"

log() { echo "==> $*"; }
die() { echo "FEHLER: $*" >&2; exit 1; }

# Pre-flight checks
command -v kubectl  >/dev/null || die "kubectl fehlt"
command -v kubeseal >/dev/null || die "kubeseal fehlt"
command -v openssl  >/dev/null || die "openssl fehlt"
[ -f "$KUBECONFIG" ] || die "Kubeconfig fehlt: $KUBECONFIG (zuerst 'make cluster-create' ausführen)"

log "Cluster prüfen"
kubectl get nodes >/dev/null || die "Cluster ist nicht erreichbar"

log "Warten bis sealed-secrets-controller bereit ist"
kubectl -n "$CONTROLLER_NAMESPACE" rollout status \
    deployment/"$CONTROLLER_NAME" --timeout=300s \
  || die "sealed-secrets-controller ist nicht bereit. Läuft Fleet bereits? ('make fleet-bootstrap')"

log "Namespaces sicherstellen"
for ns in keycloak postgresql; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

log "Zufallspasswörter erzeugen"
gen_password() {
  # 48 Bytes base64, problematische Zeichen entfernen, auf 32 Zeichen kürzen
  openssl rand -base64 48 | tr -d '/+=' | head -c 32
}
KEYCLOAK_ADMIN_PASSWORD="$(gen_password)"
KEYCLOAK_DB_PASSWORD="$(gen_password)"
POSTGRES_ADMIN_PASSWORD="$(gen_password)"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

log "Klartext-Secret-Manifeste in $TMPDIR vorbereiten"
kubectl -n keycloak create secret generic keycloak-admin \
  --from-literal=admin-password="$KEYCLOAK_ADMIN_PASSWORD" \
  --dry-run=client -o yaml > "$TMPDIR/keycloak-admin.secret.yaml"

kubectl -n keycloak create secret generic keycloak-database \
  --from-literal=password="$KEYCLOAK_DB_PASSWORD" \
  --dry-run=client -o yaml > "$TMPDIR/keycloak-database.secret.yaml"

kubectl -n postgresql create secret generic keycloak-postgresql-auth \
  --from-literal=password="$KEYCLOAK_DB_PASSWORD" \
  --from-literal=postgres-password="$POSTGRES_ADMIN_PASSWORD" \
  --dry-run=client -o yaml > "$TMPDIR/keycloak-postgresql-auth.secret.yaml"

log "Secrets mit kubeseal versiegeln"
mkdir -p "$SECRETS_DIR"
for name in keycloak-admin keycloak-database keycloak-postgresql-auth; do
  kubeseal \
    --controller-name "$CONTROLLER_NAME" \
    --controller-namespace "$CONTROLLER_NAMESPACE" \
    --format yaml \
    < "$TMPDIR/${name}.secret.yaml" \
    > "$SECRETS_DIR/${name}.sealedsecret.yaml"
  log "  geschrieben: $SECRETS_DIR/${name}.sealedsecret.yaml"
done

log "SealedSecrets direkt im Cluster anwenden"
kubectl apply -f "$SECRETS_DIR/keycloak-admin.sealedsecret.yaml"
kubectl apply -f "$SECRETS_DIR/keycloak-database.sealedsecret.yaml"
kubectl apply -f "$SECRETS_DIR/keycloak-postgresql-auth.sealedsecret.yaml"

log "Private Key des Controllers lokal sichern"
mkdir -p "$KEY_BACKUP_DIR"
chmod 700 "$KEY_BACKUP_DIR"
kubectl -n "$CONTROLLER_NAMESPACE" get secret \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > "$KEY_BACKUP_FILE"
chmod 600 "$KEY_BACKUP_FILE"
log "  geschrieben: $KEY_BACKUP_FILE (liegt auf .gitignore)"

log "Fertig."
cat <<EOF

Zusammenfassung:
  SealedSecret Dateien in platform/secrets/ wurden neu erzeugt.
  Sie sind an den aktuell laufenden Sealed-Secrets-Controller gebunden.

  Private Key gesichert in:
    $KEY_BACKUP_FILE

  Wenn du das Repository forkst und Fleet aus deinem Fork synchronisieren
  willst, committe die aktualisierten Dateien in platform/secrets/.
  Wenn du nur lokal testest, sind die Secrets bereits im Cluster.

  Admin-Passwort auslesen:
    kubectl get secret keycloak-admin -n keycloak \\
      -o jsonpath='{.data.admin-password}' | base64 -d; echo

EOF

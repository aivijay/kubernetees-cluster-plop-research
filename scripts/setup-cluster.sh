#!/bin/bash
# Full K8s + CNPG Postgres Cluster Setup
# Runs all setup scripts in order

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Full Cluster Setup ==="
echo "Project: $PROJECT_DIR"
echo ""

# Create logs dir
mkdir -p "$PROJECT_DIR/logs"

# 1. Install K3s
echo "[1/4] Installing K3s..."
bash "$SCRIPT_DIR/install-k3s.sh"

# 2. Install CNPG operator
echo "[2/4] Installing CNPG operator..."
bash "$SCRIPT_DIR/install-cnpg.sh"

# 3. Create namespace
echo "[3/4] Creating CNPG namespace..."
KUBECONFIG="/home/vijay/.kube/config-k3s"
kubectl --kubeconfig "$KUBECONFIG" create namespace cnpg-system --dry-run=client -o yaml | kubectl --kubeconfig "$KUBECONFIG" apply -f -

# 4. Deploy Postgres cluster
echo "[4/4] Deploying Postgres cluster..."
kubectl --kubeconfig "$KUBECONFIG" apply -f "$PROJECT_DIR/config/cnpg/postgres-cluster.yaml"

# Wait for cluster to be ready
echo "Waiting for Postgres cluster to initialize..."
sleep 30
kubectl --kubeconfig "$KUBECONFIG" get cluster -n cnpg-system
kubectl --kubeconfig "$KUBECONFIG" get pods -n cnpg-system

echo ""
echo "=== Setup Complete ==="
echo "Next steps:"
echo "  kubectl --kubeconfig /home/vijay/.kube/config-k3s port-forward svc/postgres-cluster-rw 5433:5432 &"
echo "  psql -h localhost -p 5433 -U postgres"
#!/bin/bash
# K3d cluster setup for CNPG Postgres
# Uses Docker (no root needed), 3 agent nodes

set -e

CLUSTER_NAME="pg-cluster"

echo "=== K3d Cluster Setup ==="
echo "Cluster: $CLUSTER_NAME"
echo ""
echo "Docker: $(docker --context default info 2>/dev/null | grep 'Version:' | head -1)"
echo ""

# Force system docker socket (k3d defaults to rootless which doesn't exist)
export DOCKER_HOST=unix:///var/run/docker.sock

# Create cluster with exposed ports
echo "[1/2] Creating k3d cluster with 3 agents..."
k3d cluster create "$CLUSTER_NAME" \
  --servers 1 \
  --agents 3 \
  --port "6443:6443" \
  --port "5433:30433" \
  --port "5434:30434" \
  --port "5435:30435" \
  --kubeconfig-update-default \
  --no-image-volume \
  --wait

# k3d auto-creates kubeconfig at ~/.kube/k3d-<cluster_name>
export KUBECONFIG="$HOME/.kube/k3d-$CLUSTER_NAME"

echo ""
echo "=== Cluster Status ==="
kubectl get nodes -o wide

echo ""
echo "✅ Cluster ready!"
echo "Kubeconfig: $KUBECONFIG"
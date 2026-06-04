#!/bin/bash
# kubernetees-cluster-plop — Stop k3d cluster
# Usage: ./stop.sh

set -e

CLUSTER_NAME="k8s-test"

echo "=== Kubernetees Cluster PLOP — Stop ==="
echo "    Stopping k3d cluster '${CLUSTER_NAME}'..."
echo "    Note: Data in emptyDir volumes will be lost on restart."
echo "    Data in local-path PVCs is preserved but requires the same nodes to restart."

k3d cluster stop ${CLUSTER_NAME}

echo "    Cluster stopped."
echo "    Run './start.sh' to restart."
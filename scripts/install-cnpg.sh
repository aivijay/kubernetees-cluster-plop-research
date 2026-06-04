#!/bin/bash
# CNPG Operator Installation
# Targets: K3s cluster at /home/vijay/.kube/config-k3s

set -e

KUBECONFIG="/home/vijay/.kube/config-k3s"
NAMESPACE="cnpg-system"
OPERATOR_VERSION="1.26.1"
OPERATOR_URL="https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-${OPERATOR_VERSION}/releases/cnpg-${OPERATOR_VERSION}.yaml"

echo "=== CNPG Operator Installation ==="
echo "Kubeconfig: $KUBECONFIG"
echo "Namespace: $NAMESPACE"
echo "Version: $OPERATOR_VERSION"
echo ""

# Create namespace
echo "Creating namespace..."
kubectl --kubeconfig "$KUBECONFIG" create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl --kubeconfig "$KUBECONFIG" apply -f -

# Install operator
echo "Installing CNPG operator..."
kubectl --kubeconfig "$KUBECONFIG" apply -f "$OPERATOR_URL" -n "$NAMESPACE"

# Wait for operator to be ready
echo "Waiting for CNPG operator..."
kubectl --kubeconfig "$KUBECONFIG" wait --for=condition=ready pod -l app.kubernetes.io/name=controller-manager -n "$NAMESPACE" --timeout=120s

echo "✅ CNPG operator installed!"
kubectl --kubeconfig "$KUBECONFIG" get pods -n "$NAMESPACE"
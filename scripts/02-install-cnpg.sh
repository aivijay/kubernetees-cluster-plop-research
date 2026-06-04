#!/bin/bash
# Install CNPG operator via Helm (recommended method)

set -e

NAMESPACE="cnpg-system"
CHART_VERSION="0.28.2"

echo "=== CNPG Operator (via Helm) ==="

# Add Helm repo
helm repo add cloudnative-pg https://cloudnative-pg.io/charts 2>/dev/null || true
helm repo update 2>&1 | tail -1

# Clean up any stale CRDs/webhooks from previous installs
for crd in $(kubectl get crds 2>/dev/null | grep 'cnpg.io' | awk '{print $1}'); do
    kubectl delete crd "$crd" 2>/dev/null
done
kubectl delete validatingwebhookconfiguration "cnpg-validating-webhook-configuration" 2>/dev/null
kubectl delete mutatingwebhookconfiguration "cnpg-mutating-webhook-configuration" 2>/dev/null

# Create namespace
kubectl create namespace "$NAMESPACE" 2>/dev/null || true

# Install via Helm
helm install cnpg cloudnative-pg/cloudnative-pg \
    --namespace "$NAMESPACE" \
    --version "$CHART_VERSION" \
    2>&1

# Wait for operator
echo "Waiting for CNPG operator..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=cloudnative-pg \
    -n "$NAMESPACE" \
    --timeout=120s 2>&1

echo ""
kubectl get pods -n "$NAMESPACE"
echo ""
echo "✅ CNPG operator installed via Helm!"
#!/bin/bash
# K3s Installation Script
# Target: Local laptop, non-root user (vijay)
# Port: 6443 (non-standard)
# User: vijay (no root)

set -e

K3S_VERSION="v1.31.0"
KUBECONFIG_PATH="/home/vijay/.kube/config-k3s"
API_PORT="6443"

echo "=== K3s Installation (non-root) ==="
echo "API Port: $API_PORT"
echo "Kubeconfig: $KUBECONFIG_PATH"
echo ""

# Download k3s binary
echo "Downloading k3s..."
curl -sfL https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s -o /tmp/k3s
chmod +x /tmp/k3s

# Install to user local bin
mkdir -p /home/vijay/bin
mv /tmp/k3s /home/vijay/bin/k3s

# Add to PATH if not already there
if ! grep -q '/home/vijay/bin' ~/.bashrc 2>/dev/null; then
    echo 'export PATH="/home/vijay/bin:$PATH"' >> ~/.bashrc
fi

export PATH="/home/vijay/bin:$PATH"

# Start k3s server (single node)
echo "Starting K3s server..."
nohup k3s server \
    --cluster-init \
    --tls-san 127.0.0.1 \
    --write-kubeconfig "$KUBECONFIG_PATH" \
    --write-kubeconfig-mode 644 \
    --bind-address 127.0.0.1 \
    --https-listen-port 6443 \
    --disable traefik \
    --disable servicelb \
    --disable metrics-server \
    > /home/vijay/projects/kubernetees-cluster-plop-research/logs/k3s.log 2>&1 &

echo "K3s PID: $!"
echo "Waiting for cluster to start..."
sleep 10

# Verify
if kubectl --kubeconfig "$KUBECONFIG_PATH" get nodes 2>/dev/null; then
    echo "✅ K3s cluster is up!"
else
    echo "❌ Cluster not ready yet. Check logs at logs/k3s.log"
fi
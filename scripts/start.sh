#!/bin/bash
# kubernetees-cluster-plop — Start cluster and deploy all services
# Usage: ./start.sh [--fresh]

set -e

# k3d needs system docker socket
export DOCKER_HOST="unix:///var/run/docker.sock"

# Define cluster name early — used throughout
CLUSTER_NAME="k8s-test"

# k3d merges config into ~/.kube/config (not ~/.kube/k3d-<cluster>)
# Use default kubeconfig path — kubectl finds it there
export KUBECONFIG="${HOME}/.kube/config"

# Fix kubeconfig server address — k3d writes "https://0.0.0.0:PORT" but kubectl needs "https://127.0.0.1:PORT"
if grep -q "server: https://0.0.0.0:" "${KUBECONFIG}" 2>/dev/null; then
    sed -i 's|https://0.0.0.0:|https://127.0.0.1:|g' "${KUBECONFIG}"
fi

NAMESPACE="cnpg-system"

echo "=== Kubernetees Cluster PLOP — Start ==="

# Start k3d cluster if not running
if ! k3d cluster list 2>/dev/null | grep -q "${CLUSTER_NAME}.*running"; then
    echo "[1/6] Starting k3d cluster..."
    k3d cluster start ${CLUSTER_NAME}
    echo "    Waiting for nodes..."
    kubectl wait --for=condition=ready node --all --timeout=120s
else
    echo "[1/6] Cluster already running"
fi

kubectl config use-context k3d-${CLUSTER_NAME} > /dev/null 2>&1

# Clean namespace if --fresh
if [[ "${1}" == "--fresh" ]]; then
    echo "[2/6] Fresh start — cleaning namespace..."
    kubectl delete ns ${NAMESPACE} --ignore-not-found
    kubectl delete crd clusters.postgresql.cnpg.io --ignore-not-found 2>/dev/null || true
    kubectl delete crd backups.postgresql.cnpg.io --ignore-not-found 2>/dev/null || true
    kubectl delete crd databases.postgresql.cnpg.io --ignore-not-found 2>/dev/null || true
    kubectl delete clusterrolebindings cnpg-webhook-binding 2>/dev/null || true
    kubectl delete clusterrole cnpg-webhook-service 2>/dev/null || true
    kubectl create ns ${NAMESPACE}
else
    echo "[2/6] Preserving existing namespace (use --fresh to reset)"
fi

# Create secrets
echo "[3/6] Creating secrets..."
# CNPG Cluster spec uses initdb.secret.name=postgres-secret (password: postgres123)
# superuserSecretarname controls which secret holds the superuser password
kubectl create secret generic postgres-auth \
    --from-literal=username=postgres \
    --from-literal=password=postgres123 \
    -n ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
kubectl create secret generic mongo-init \
    --from-literal=username=admin \
    --from-literal=password=mongo123 \
    -n ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
kubectl create secret generic activemq-secret \
    --from-literal=username=admin \
    --from-literal=password=admin123 \
    -n ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true

# Install CNPG operator
echo "[4/6] Installing CNPG operator..."
helm repo add cnpg https://cloudnative-pg.github.io/charts --force-update 2>/dev/null
helm repo update 2>/dev/null
helm upgrade --install cnpg-operator cnpg/cloudnative-pg \
    --namespace ${NAMESPACE} \
    --version 0.28.2 \
    --set installCRDs=false \
    --wait --timeout 120s 2>/dev/null || true

echo "    Waiting for CNPG operator..."
kubectl wait --for=condition=ready pod -n ${NAMESPACE} -l app.kubernetes.io/name=cloudnative-pg --timeout=180s 2>/dev/null || true

# Pooler CRD workaround (CNPG 1.27+ bug)
if ! kubectl get crd poolers.postgresql.cnpg.io >/dev/null 2>&1; then
    echo "    Installing Pooler CRD (CNPG 1.27+ workaround)..."
    if [[ ! -f /tmp/pooler-crd.yaml ]]; then
        curl -sL https://github.com/cloudnative-pg/cloudnative-pg/archive/refs/tags/v1.26.1.tar.gz -o /tmp/cnpg.tar.gz
        cd /tmp && tar xzf cnpg.tar.gz
        python3 -c "
import yaml
with open('/tmp/cloudnative-pg-1.26.1/config/crd/bases/postgresql.cnpg.io_poolers.yaml') as f:
    doc = yaml.safe_load(f)
doc['metadata']['annotations'] = {k:v for k,v in doc['metadata']['annotations'].items() if 'kubectl.kubernetes.io' not in k and 'lastAppliedConfiguration' not in k}
print(yaml.dump(doc))
" > /tmp/pooler-crd.yaml
    fi
    kubectl apply -f /tmp/pooler-crd.yaml
fi

# Deploy PostgreSQL
echo "[5/6] Deploying PostgreSQL cluster..."
kubectl apply -n ${NAMESPACE} -f config/cnpg/postgres-cluster.yaml 2>/dev/null || true
# Deploy NodePort services for PostgreSQL
kubectl apply -n ${NAMESPACE} -f - << 'EOF' 2>/dev/null || true
apiVersion: v1
kind: Service
metadata:
  name: postgres-cluster-rw-np
  namespace: cnpg-system
spec:
  type: NodePort
  selector:
    cnpg.io/cluster: postgres-cluster
    cnpg.io/instanceRole: primary
  ports:
    - port: 5432
      nodePort: 30433
      name: postgres-rw
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-cluster-ro-np
  namespace: cnpg-system
spec:
  type: NodePort
  selector:
    cnpg.io/cluster: postgres-cluster
    cnpg.io/instanceRole: replica
  ports:
    - port: 5432
      nodePort: 30434
      name: postgres-ro
EOF

# Deploy MongoDB
echo "[6/6] Deploying MongoDB..."
kubectl apply -n ${NAMESPACE} -f config/mongodb/mongodb.yaml 2>/dev/null || true

# Deploy ActiveMQ
kubectl apply -n ${NAMESPACE} -f config/activemq/activemq.yaml 2>/dev/null || true

# Wait for pods
echo ""
echo "    Waiting for all pods to be ready..."
kubectl wait --for=condition=ready pod -n ${NAMESPACE} -l app.kubernetes.io/instance=cnpg-operator --timeout=120s 2>/dev/null || true
kubectl wait --for=condition=ready pod -n ${NAMESPACE} -l app=mongodb --timeout=180s 2>/dev/null || true
kubectl wait --for=condition=ready pod -n ${NAMESPACE} -l app=activemq --timeout=240s 2>/dev/null || true

# Wait for primary to be ready, then set postgres password to mongo123
echo "    Setting postgres password..."
kubectl wait --for=condition=ready pod -n ${NAMESPACE} -l cnpg.io/cluster=postgres-cluster,cnpg.io/instance-role=primary --timeout=120s 2>/dev/null || true
PRIMARY_POD=$(kubectl get pod -n ${NAMESPACE} -l cnpg.io/cluster=postgres-cluster,cnpg.io/instance-role=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -n "${PRIMARY_POD}" ]]; then
    kubectl exec -it ${PRIMARY_POD} -n ${NAMESPACE} -- psql -U postgres -c "ALTER USER postgres WITH PASSWORD 'mongo123';" 2>/dev/null || true
fi

# Initialize MongoDB replica set (if not already done)
echo ""
echo "    Checking MongoDB replica set..."
RS_OK=$(kubectl exec -it mongodb-0 -n ${NAMESPACE} -- mongosh --quiet --username admin --password mongo123 --authenticationDatabase admin --eval 'rs.status().ok' 2>/dev/null || echo "0")
if [[ "${RS_OK}" != "1" ]]; then
    echo "    Initializing MongoDB replica set rs0..."
    kubectl exec -it mongodb-0 -n ${NAMESPACE} -- mongosh --quiet --username admin --password mongo123 --authenticationDatabase admin --eval '
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "mongodb-0.mongodb-headless.cnpg-system.svc.cluster.local:27017" },
    { _id: 1, host: "mongodb-1.mongodb-headless.cnpg-system.svc.cluster.local:27017" },
    { _id: 2, host: "mongodb-2.mongodb-headless.cnpg-system.svc.cluster.local:27017" }
  ]
});
' 2>/dev/null || true
else
    echo "    MongoDB replica set already initialized"
fi

echo ""
echo "=== Cluster Status ==="
kubectl get pods -n ${NAMESPACE} 2>/dev/null

echo ""
echo "=== Connection Info ==="
echo "  PostgreSQL RW: localhost:30433 (postgres/mongo123)"
echo "  PostgreSQL RO: localhost:30434 (postgres/mongo123)"
echo "  MongoDB:       localhost:30435 (admin/mongo123)"
echo "  ActiveMQ Core: localhost:30436 (admin/admin123)"
echo "  ActiveMQ HTTP: http://localhost:30437/console"
echo ""
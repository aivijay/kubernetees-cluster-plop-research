#!/bin/bash
# kubernetees-cluster-plop — Cluster status check
# Usage: ./status.sh

# k3d needs system docker socket
export DOCKER_HOST="unix:///var/run/docker.sock"
# Fix kubeconfig server address (k3d bug: writes 0.0.0.0 instead of 127.0.0.1)
export KUBECONFIG="${HOME}/.kube/config"
if grep -q "server: https://0.0.0.0:" "${KUBECONFIG}" 2>/dev/null; then
    sed -i 's|https://0.0.0.0:|https://127.0.0.1:|g' "${KUBECONFIG}"
fi

NAMESPACE="cnpg-system"

echo "=== Kubernetees Cluster PLOP — Status ==="
echo ""

# Cluster
echo "[Cluster]"
CLUSTER_STATUS=$(DOCKER_HOST=unix:///var/run/docker.sock k3d cluster list 2>/dev/null | grep "k8s-test" | awk '{print $2" / "$3" / "$4}')
if [[ -n "${CLUSTER_STATUS}" ]]; then
    echo "  Cluster: UP (${CLUSTER_STATUS})"
else
    echo "  Cluster: STOPPED"
    exit 1
fi
kubectl get nodes -o wide 2>/dev/null | tail -n +2 | awk '{printf "  %-30s %-10s %-10s\n", $1, $2, $4}'
echo ""

# Pods
echo "[Pods]"
kubectl get pods -n ${NAMESPACE} -o wide 2>/dev/null | tail -n +2 | awk '{printf "  %-35s %-10s %-5s %s\n", $1, $3, $2, $4}'
echo ""

# Services
echo "[Services]"
kubectl get svc -n ${NAMESPACE} 2>/dev/null | tail -n +2 | grep -E "NodePort|ClusterIP" | awk '{printf "  %-30s %-15s %s\n", $1, $2, $5}'
echo ""

# PostgreSQL
echo "[PostgreSQL]"
PG_READY=$(kubectl get pods -n ${NAMESPACE} -l cnpg.io/cluster=postgres-cluster,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
if [[ "${PG_READY}" == "True" ]]; then
    echo "  Cluster: READY"
    kubectl exec -it postgres-cluster-1 -n ${NAMESPACE} -- psql -U postgres -c "SELECT pg_is_in_recovery() as is_replica;" 2>/dev/null | grep -v "^SELECT\|^--" | head -2 || true
else
    echo "  Cluster: NOT READY"
fi

# MongoDB
echo ""
echo "[MongoDB]"
kubectl exec -it mongodb-0 -n ${NAMESPACE} -- mongosh --quiet --username admin --password mongo123 --authenticationDatabase admin --eval '
rs.status().members.forEach(m => print(m.name.split(".")[0] + " : " + m.stateStr + " (health:" + m.health + ")"))
' 2>/dev/null || echo "  Cannot connect (may need user setup)"

# ActiveMQ
echo ""
echo "[ActiveMQ]"
AMQP_STATUS=$(curl -s --connect-timeout 3 -o /dev/null -w "%{http_code}" -H "Host: localhost" http://127.0.0.1:30437/ 2>/dev/null || echo "000")
if [[ "${AMQP_STATUS}" == "302" || "${AMQP_STATUS}" == "200" ]]; then
    echo "  Master:  READY (HTTP ${AMQP_STATUS})"
else
    if nc -zv 127.0.0.1 30437 -w 2 2>/dev/null; then
        echo "  Master:  PORT OPEN (HTTP unreachable — k3d LB known issue)"
    else
        echo "  Master:  NOT READY"
    fi
fi

echo ""
echo "=== Connection Info ==="
echo "  PostgreSQL RW: 127.0.0.1:30433  (postgres/mongo123)"
echo "  PostgreSQL RO: 127.0.0.1:30434  (postgres/mongo123)"
echo "  MongoDB:       localhost:30435  (admin/mongo123)"
echo "  ActiveMQ Core: localhost:30436  (admin/admin123)"
echo "  ActiveMQ HTTP: http://localhost:30437/console"
echo "  ActiveMQ AMQP: localhost:30438  (admin/admin123)"
echo "  ActiveMQ STOMP: localhost:30439 (admin/admin123)"
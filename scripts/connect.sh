#!/bin/bash
# kubernetees-cluster-plop — Connect to any service
# Usage: ./connect.sh [pg|pgs|mongo|amqp|amqp-http|console]

# k3d needs system docker socket
export DOCKER_HOST="unix:///var/run/docker.sock"
export KUBECONFIG="${HOME}/.kube/config"
# Fix kubeconfig server address (k3d bug)
if grep -q "server: https://0.0.0.0:" "${KUBECONFIG}" 2>/dev/null; then
    sed -i 's|https://0.0.0.0:|https://127.0.0.1:|g' "${KUBECONFIG}"
fi

NAMESPACE="cnpg-system"

connect_pg() {
    echo "PostgreSQL — Read/Write (primary)"
    echo "  Host:     127.0.0.1:30433"
    echo "  User:     postgres"
    echo "  Password: mongo123"
    echo "  Database: postgres"
    echo ""
    echo "  Command:"
    echo "    PGPASSWORD=mongo123 psql -h 127.0.0.1 -p 30433 -U postgres -d postgres"
    echo ""
    PGPASSWORD=mongo123 psql -h 127.0.0.1 -p 30433 -U postgres -d postgres
}

connect_pgs() {
    echo "PostgreSQL — Read/Only (replica)"
    echo "  Host:     127.0.0.1:30434"
    echo "  User:     postgres"
    echo "  Password: mongo123"
    echo "  Database: postgres"
    echo ""
    echo "  Command:"
    echo "    PGPASSWORD=mongo123 psql -h 127.0.0.1 -p 30434 -U postgres -d postgres"
    echo ""
    PGPASSWORD=mongo123 psql -h 127.0.0.1 -p 30434 -U postgres -d postgres
}

connect_mongo() {
    echo "MongoDB — Replica Set rs0"
    echo "  Host:     127.0.0.1:30435"
    echo "  User:     admin"
    echo "  Password: mongo123"
    echo "  AuthDB:   admin"
    echo ""
    echo "  Command:"
    echo "    mongosh -h 127.0.0.1:30435 -u admin -p mongo123 --authenticationDatabase admin"
    echo ""
    mongosh -h 127.0.0.1:30435 -u admin -p mongo123 --authenticationDatabase admin
}

connect_amqp() {
    echo "ActiveMQ Artemis — Core AMQP"
    echo "  Host:     localhost:30436"
    echo "  User:     admin"
    echo "  Password: admin123"
    echo ""
    echo "  Connection URL:"
    echo "    amqp://admin:admin123@localhost:30436"
}

connect_amqp_http() {
    echo "ActiveMQ Artemis — HTTP Console"
    echo "  URL:      http://localhost:30437/console"
    echo "  User:     admin"
    echo "  Password: admin123"
}

case "${1}" in
    pg|pgres|postgres-rw)
        connect_pg
        ;;
    pgs|pgre|pgsro|postgres-ro)
        connect_pgs
        ;;
    mongo|mongodb|rs)
        connect_mongo
        ;;
    amqp|activemq|amqp-core)
        connect_amqp
        ;;
    amqp-http|amqp_http|http|console)
        connect_amqp_http
        ;;
    "")
        echo "Usage: ./connect.sh <service>"
        echo ""
        echo "  pg          — PostgreSQL read/write (port 30433)"
        echo "  pgs         — PostgreSQL read-only (port 30434)"
        echo "  mongo       — MongoDB replica set (port 30435)"
        echo "  amqp        — ActiveMQ Core AMQP (port 30436)"
        echo "  amqp-http   — ActiveMQ HTTP console (port 30437)"
        echo ""
        echo "  Examples:"
        echo "    ./connect.sh pg        # Connect to PostgreSQL RW"
        echo "    ./connect.sh mongo     # Connect to MongoDB"
        echo "    ./connect.sh amqp      # Show ActiveMQ connection info"
        echo "    ./connect.sh console   # Open ActiveMQ console URL"
        ;;
    *)
        echo "Unknown service: ${1}"
        echo "Run without arguments to see available services."
        ;;
esac
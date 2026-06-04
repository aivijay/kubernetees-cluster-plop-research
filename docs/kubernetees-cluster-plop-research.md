# Kubernetes Cluster with CNPG Postgres — Research Doc

**Project:** kubernetees-cluster-plop-research  
**User:** vijay  
**Date:** 2026-06-03  
**Status:** Research & Planning

---

## Goals

1. 3-node Postgres cluster on K8s (K3s) on this laptop
2. Non-standard ports (not 5432)
3. Automatic failover
4. Synchronous replication
5. Read scaling (read replicas)
6. CNPG operator for management
7. Self-contained under `/home/vijay/projects/kubernetees-cluster-plop-research/`
8. No root-level setup on laptop

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Laptop (host)                                      │
│                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌────────────┐ │
│  │  K3s Node   │  │  K3s Node   │  │  K3s Node  │ │
│  │  (master)   │  │  (worker-1) │  │ (worker-2) │ │
│  │  :6443      │  │             │  │            │ │
│  │  :5433 (rw) │  │  :5434 (ro) │  │  :5435 (ro)│ │
│  │  pg-1       │  │  pg-2       │  │  pg-3      │ │
│  └─────────────┘  └─────────────┘  └────────────┘ │
│                                                     │
│  Longhorn Storage (local-path for dev)              │
└─────────────────────────────────────────────────────┘
```

---

## Port Assignment

| Service        | Host Port | Node   | CNPG Service    |
|----------------|-----------|--------|-----------------|
| K8s API        | 6443      | master | -               |
| Metrics Server | 10249     | master | -               |
| Postgres rw    | 5433      | node-1 | postgres-cluster-rw |
| Postgres ro-1  | 5434      | node-2 | postgres-cluster-ro |
| Postgres ro-2  | 5435      | node-3 | postgres-cluster-ro |
| Longhorn UI    | 30880     | master | longhorn-frontend |

---

## Components

### 1. K3s (Kubernetes)
- Lightweight K8s, perfect for laptop/local dev
- Uses containerd instead of Docker
- Single binary, ~60MB
- Default: `/etc/rancher/k3s/k3s.yaml` for kubectl config

### 2. CNPG (CloudNativePG)
- Operator for Postgres on K8s
- Manages: pods, services, replication slots, failover, backups
- Creates two services automatically:
  - `<cluster>-rw` — primary (writes)
  - `<cluster>-ro` — replicas (reads)
- Sync replication: quorum-based synchronous
- Failover: automatic via leader election

### 3. Storage — Local-Path (Dev)
- K3s built-in storage (no extra install)
- Each PVC lives on the node that runs the pod
- ⚠️ NOT HIGHLY AVAILABLE — if node dies, PVC is gone
- For true HA: Longhorn (distributed block storage)

---

## CNPG Cluster Spec

**File:** `../config/cnpg/postgres-cluster.yaml`

Key settings:
- `instances: 3` — 1 primary + 2 replicas
- `readOnlyInstances: 1` — dedicated read endpoint
- `replicationSlots.synchronizationPolicy: quorum` — sync replication
- `primaryUpdateStrategy: unsupervised` — auto-failover to healthiest replica
- `imageName: ghcr.io/cloudnative-pg/postgresql:16.1`
- Custom ports via pod env: `POSTGRES_PORT: 5432`

---

## Setup Phases

### Phase 1 — K3s Installation
**Script:** `../scripts/install-k3s.sh`

```bash
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644 --port 6443
```

- `--write-kubeconfig-mode 644` — allows non-root kubectl access
- `--port 6443` — non-standard API port
- Kubeconfig: `/home/vijay/.kube/config-k3s`

### Phase 2 — CNPG Operator
**Manifests:** `../config/cnpg/operator.yaml`

```bash
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pchg/cloudnative-pg/release-1.26/releases/cnpg-1.26.1.yaml
```

### Phase 3 — Storage (Local-Path)
K3s provisions automatically via `local-path` StorageClass. No extra setup.

### Phase 4 — Postgres Cluster
```bash
kubectl apply -f ../config/cnpg/postgres-cluster.yaml
```

### Phase 5 — Port Forwarding / NodePort Access
```bash
# Primary (writes)
kubectl port-forward svc/postgres-cluster-rw 5433:5432 &

# Replicas (reads)
kubectl port-forward svc/postgres-cluster-ro 5434:5432 &
kubectl port-forward --namespace cnpg-system svc/postgres-cluster-ro 5435:5432 &
```

---

## Connecting

```bash
# Write endpoint
psql -h localhost -p 5433 -U postgres

# Read endpoint (load-balanced across replicas)
psql -h localhost -p 5434 -U postgres
```

---

## Failover Test

```bash
# Find primary pod
kubectl get pods -n cnpg-system -l cnpg.io/cluster=postgres-cluster -l role=primary

# Delete primary — CNPG auto-promotes a replica
kubectl delete pod <primary-pod-name> -n cnpg-system
```

CNPG will detect the failure, elect a new primary, and update the `-rw` endpoint.

---

## Obsidian Notes

- `../docs/atomic-notes/` — atomic notes for each concept:
  - K3s-Installation.md
  - CNPG-Operator.md
  - Postgres-Replication-Modes.md
  - Failover-Testing.md
  - Local-Path-Storage.md

---

## References

- CNPG Docs: https://cloudnative-pg.io/documentation/
- K3s: https://docs.k3s.io/
- Local Path Provisioner: https://github.com/rancher/local-path-provisioner

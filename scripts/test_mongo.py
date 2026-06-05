#!/usr/bin/env python3
"""MongoDB — insert and find documents via pymongo"""
from pymongo import MongoClient

# For Spring Boot inside k3d cluster, use the RW service:
#   host="mongodb-rw.cnpg-system.svc.cluster.local", port=27017
#
# From outside (host): NodePort load-balances across all pods,
#   may hit secondary (not writable). Use directConnection + specific pod IP.
#
# We use directConnection to target the primary directly by pod IP.
# Get primary pod IP first via kubectl.

import subprocess, sys

# Get primary pod IP
try:
    result = subprocess.run(
        ["kubectl", "get", "pod", "mongodb-0", "-n", "cnpg-system",
         "-o", "jsonpath={.status.podIP}"],
        capture_output=True, text=True, timeout=5
    )
    PRIMARY_IP = result.stdout.strip()
except Exception as e:
    print(f"Failed to get primary pod IP: {e}")
    sys.exit(1)

print(f"MongoDB Test — targeting primary mongodb-0 @ {PRIMARY_IP}\n")

HOST = PRIMARY_IP
PORT = 27017

client = MongoClient(
    host=HOST, port=PORT,
    username="admin", password="mongo123",
    authSource="admin",
    directConnection=True,
    serverSelectionTimeoutMS=5000,
)

try:
    client.admin.command("ping")
    print("[1] Connected to PRIMARY.\n")
except Exception as e:
    print(f"Connection failed: {e}")
    exit(1)

db = client["testdb"]
col = db["messages"]

# Insert
print("[2] Inserting 3 documents...")
for i in range(1, 4):
    doc = {"msg": f"Hello #{i}", "ts": __import__("time").time()}
    result = col.insert_one(doc)
    print(f"    Inserted _id={result.inserted_id} → {doc['msg']}")

# Find
print("\n[3] Finding all documents in collection:")
for doc in col.find():
    print(f"    {doc['_id']} → {doc['msg']}")

# Cleanup
n = col.delete_many({})
print(f"\n[4] Cleaned up {n.deleted_count} documents")

client.close()
print("Done.")
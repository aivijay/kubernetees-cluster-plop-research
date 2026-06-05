#!/usr/bin/env python3
"""ActiveMQ — produce and consume messages via STOMP"""
import time
import stomp

QUEUE = "/queue/test"
HOST = "127.0.0.1"   # NodePort from host; use "activemq-rw.cnpg-system.svc.cluster.local" inside cluster
PORT = 30436

print("ActiveMQ Test — produce + consume\n")

# Connect producer
print("[1] Connecting producer...")
conn = stomp.Connection([(HOST, PORT)])
conn.connect("admin", "admin123")
print("    Connected.\n")

# Send messages
print("[2] Sending 3 test messages...")
for i in range(1, 4):
    msg = f"Hello #{i} at {time.strftime('%H:%M:%S')}"
    conn.send(QUEUE, msg, headers={"persistent": "true"})
    print(f"    [SENT] {msg}")

conn.disconnect()
print("\n[3] Disconnected producer.\n")

# Connect consumer
print("[4] Connecting consumer (read remaining messages)...")
conn2 = stomp.Connection([(HOST, PORT)])
received = []

class CaptureListener(stomp.ConnectionListener):
    def on_message(self, frame):
        received.append(frame.body)
        print(f"    [RECV] {frame.body}")

conn2.set_listener("", CaptureListener())
conn2.connect("admin", "admin123")
conn2.subscribe(QUEUE, id="test-sub", ack="auto")

time.sleep(2)
conn2.disconnect()

print(f"\n[5] Received {len(received)} message(s)")
if received:
    for m in received:
        print(f"    → {m}")
else:
    print("    (no messages in queue — try re-running)")

print("\nDone.")
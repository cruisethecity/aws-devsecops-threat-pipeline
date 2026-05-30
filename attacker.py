import socket
import time
import random

# Replace this with your actual RDS Endpoint from the terraform output
TARGET_IP = "terraform-20260527191905303600000001.c4d4m6s0uyoa.us-east-1.rds.amazonaws.com"
PORT = 5432

# Simulate different "bot" behaviors
USER_AGENTS = ["bot-net-01", "bot-net-02", "script-kiddie-pro", "scanner-v1"]
PAYLOADS = [
    b"user=admin\0password=password\0",
    b"user=root\0password=123456\0",
    b"user=dbadmin\0password=Password123!\0"
]

print(f"[*] Initiating multi-vector brute-force simulation against {TARGET_IP}:{PORT}...")

attack_count = 0
while True:
    try:
        # Randomize the "bot" identity
        bot_id = random.choice(USER_AGENTS)
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2)
        
        s.connect((TARGET_IP, PORT))
        
        # Send a payload to generate distinct traffic patterns in VPC Flow Logs
        payload = random.choice(PAYLOADS)
        s.sendall(payload)
        
        attack_count += 1
        print(f"[+] Attack {attack_count} via {bot_id} sent! Payload size: {len(payload)} bytes.")
        
        s.close()
    except Exception as e:
        # Connection failed is actually a 'Good' log for Kenny to see
        print(f"[-] Connection attempt failed (Blocked or Refused).")
    
    # Randomize wait time (0.5 to 2 seconds) to avoid easy pattern detection
    time.sleep(random.uniform(0.5, 2.0))
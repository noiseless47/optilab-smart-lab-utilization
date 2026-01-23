# Bastion Host Deployment Log

**Date:** December 3, 2025  
**Network:** 192.168.0.x  
**Systems:**
- 192.168.0.10 - Lab computer (target)
- 192.168.0.11 - Lab computer (target)
- 192.168.0.12 - Bastion host (jump server)
- 192.168.0.13 - Collector (OptiLab server)

---

## 🚀 Quick Start: Add New Target System

To add a new target lab computer (e.g., 192.168.0.10), run this **ONE command** on the target:

```bash
mkdir -p ~/.ssh && echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILtfJLWEjSpjgmQM5Aui27hyQsY1liZdPdPPay14+miS bastion-to-targets" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
```

Then test from collector:
```bash
ssh 192.168.0.10 hostname
```

That's it! The bastion routing will work automatically.

---

## Phase 1: Bastion Host Setup (192.168.0.12)

### 1.1 Generate Target SSH Key
```bash
sudo ssh-keygen -t ed25519 -f /root/.ssh/target_key -N "" -C "bastion-to-targets"
```

### 1.2 Copy Target Key to Jump User
```bash
sudo cp /root/.ssh/target_key /home/jump/.ssh/target_key
sudo cp /root/.ssh/target_key.pub /home/jump/.ssh/target_key.pub
sudo chown jump:jump /home/jump/.ssh/target_key /home/jump/.ssh/target_key.pub
sudo chmod 600 /home/jump/.ssh/target_key
```

### 1.3 Configure Jump User SSH Config
```bash
sudo tee /home/jump/.ssh/config << 'EOF'
Host 192.168.0.10 192.168.0.11
    IdentityFile ~/.ssh/target_key
    User rvce
    StrictHostKeyChecking accept-new
EOF

sudo chown jump:jump /home/jump/.ssh/config
sudo chmod 600 /home/jump/.ssh/config
```

### 1.4 View Target Public Key
```bash
sudo cat /root/.ssh/target_key.pub
# Output: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILtfJLWEjSpjgmQM5Aui27hyQsY1liZdPdPPay14+miS bastion-to-targets
```

### 1.5 Test Jump User Connection to Target
```bash
sudo -u jump ssh rvce@192.168.0.11 hostname
# Output: rvce-ThinkCentre-M75s-Gen-5
```

---

## Phase 2: Target Systems Setup (192.168.0.10, 192.168.0.11)

### 2.1 Add Target Key to Authorized Keys (Run on EACH target)
```bash
mkdir -p ~/.ssh && echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILtfJLWEjSpjgmQM5Aui27hyQsY1liZdPdPPay14+miS bastion-to-targets" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
```

---

## Phase 3: Collector Setup (192.168.0.13)

### 3.1 Fix Bastion Key Permissions
```bash
chmod 600 ~/.ssh/bastion_key
```

### 3.2 Make Scripts Executable
```bash
chmod +x ssh_script.sh ssh_bastion_wrapper.sh scanner.sh metrics_collector.sh bastion_config.sh
```

### 3.3 Test Direct Bastion Connection
```bash
ssh -i ~/.ssh/bastion_key jump@192.168.0.12 echo 'Bastion works!'
# Output: Bastion works!
```

### 3.4 Copy Target Keys to Collector (from bastion)
```bash
sudo scp -o StrictHostKeyChecking=no /root/.ssh/target_key /root/.ssh/target_key.pub aayush@192.168.0.13:~/
```

### 3.5 Move Target Keys to SSH Directory (on collector)
```bash
mv ~/target_key ~/.ssh/
mv ~/target_key.pub ~/.ssh/
chmod 600 ~/.ssh/target_key
```

### 3.6 Create SSH Config on Collector
```bash
cat > ~/.ssh/config << 'EOF'
Host bastion
    HostName 192.168.0.12
    User jump
    Port 22
    IdentityFile ~/.ssh/bastion_key
    StrictHostKeyChecking accept-new

Host 192.168.0.10 192.168.0.11
    User rvce
    ProxyJump bastion
    IdentityFile ~/.ssh/target_key
    StrictHostKeyChecking accept-new
EOF

chmod 600 ~/.ssh/config
```

### 3.7 Test End-to-End Connection
```bash
ssh 192.168.0.11 hostname
# Output: rvce-ThinkCentre-M75s-Gen-5
```

### 3.8 Test Metrics Collection
```bash
ssh 192.168.0.11 'uptime && free -h && df -h'
# Successfully retrieves system metrics through bastion
```

---

## Phase 4: Running Collection Scripts

### 4.1 Test SSH Script with Correct Parameters
```bash
cd ~/optilab-smart-lab-utilization-main/collector
SSH_USER=rvce SSH_KEY=~/.ssh/target_key ./ssh_script.sh --single 192.168.0.11
```

---

## Verification Commands

### From Bastion (192.168.0.12)
```bash
# View jump user authorized keys
sudo cat /home/jump/.ssh/authorized_keys

# View jump user SSH config
sudo cat /home/jump/.ssh/config

# View jump user SSH directory
sudo ls -la /home/jump/.ssh/

# Test connection as jump user
sudo -u jump ssh rvce@192.168.0.11 hostname
```

### From Collector (192.168.0.13)
```bash
# Test bastion connection
ssh -i ~/.ssh/bastion_key jump@192.168.0.12 "echo test"

# Test end-to-end via ProxyJump
ssh 192.168.0.11 hostname
ssh 192.168.0.10 hostname

# View SSH config
cat ~/.ssh/config

# List SSH keys
ls -la ~/.ssh/

# Extract public key from private key
ssh-keygen -y -f ~/.ssh/bastion_key
ssh-keygen -y -f ~/.ssh/target_key
```

---

## SSH Key Summary

### Bastion Key (Collector → Bastion)
- **Private Key Location (Collector):** `~/.ssh/bastion_key`
- **Public Key Location (Collector):** `~/.ssh/bastion_key.pub`
- **Public Key Content:** `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJt0g4D0biWwFh/PoRCkru/hnYj5mlFiUELAo84Q4P74 collector-to-bastion`
- **Authorized On:** Bastion host `/home/jump/.ssh/authorized_keys`

### Target Key (Bastion → Targets)
- **Private Key Location (Bastion):** `/home/jump/.ssh/target_key`
- **Private Key Location (Collector):** `~/.ssh/target_key`
- **Public Key Location:** `~/.ssh/target_key.pub`
- **Public Key Content:** `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILtfJLWEjSpjgmQM5Aui27hyQsY1liZdPdPPay14+miS bastion-to-targets`
- **Authorized On:** Target systems `~/.ssh/authorized_keys` (0.10, 0.11)

---

## Connection Flow

```
Collector (192.168.0.13)
    |
    | Uses: bastion_key
    v
Bastion (192.168.0.12) - Jump User
    |
    | Uses: target_key (from jump user's SSH config)
    v
Target Lab Computer (192.168.0.10 or 192.168.0.11)
```

---

## Important Notes

1. **Username on targets:** `rvce` (NOT `admin`)
2. **Jump user on bastion:** `jump`
3. **ProxyJump:** SSH automatically chains through bastion using `-J` or `ProxyJump` config
4. **Target key must exist on both bastion AND collector** for ProxyJump to work
5. **SSH config on collector** simplifies commands (can use just `ssh 192.168.0.11` instead of full ProxyJump syntax)

---

## Troubleshooting Commands

### Check SSH Connection with Verbose Output
```bash
ssh -vvv -i ~/.ssh/bastion_key jump@192.168.0.12 "echo test"
ssh -vvv 192.168.0.11 hostname
```

### Test SSH Key Authentication
```bash
ssh-keygen -y -f ~/.ssh/bastion_key  # Extract public key from private
ssh -i ~/.ssh/bastion_key jump@192.168.0.12  # Test specific key
```

### Check File Permissions
```bash
ls -la ~/.ssh/
# Keys should be 600 (rw-------)
# Config should be 600 (rw-------)
# Directory should be 700 (rwx------)
```

### Test ProxyJump Manually
```bash
ssh -i ~/.ssh/bastion_key -J jump@192.168.0.12:22 -i ~/.ssh/target_key rvce@192.168.0.11 hostname
```

---

## Status: ✅ WORKING

- [x] Bastion host configured
- [x] Jump user created and configured
- [x] SSH keys generated and distributed
- [x] Collector can connect to bastion
- [x] Bastion can connect to targets
- [x] End-to-end ProxyJump working
- [x] Metrics collection tested successfully
- [ ] Target key added to 192.168.0.10 (pending)
- [ ] Database setup on collector (pending)

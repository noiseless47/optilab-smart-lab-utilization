# Adding New Target Systems to OptiLab Collection Network

This guide explains how to add new lab computer systems to the OptiLab metrics collection infrastructure using the bastion host architecture.

## Network Architecture Overview

```
Target System (0.10, 0.11, etc.)
    ↑ (rvce user, target_key auth)
Bastion Host (0.12 - jump user, target_key)
    ↑ (jump user, bastion_key auth)
Collector (0.13 - aayush user, bastion_key)
    ↑
Database & Frontend
```

## Prerequisites

Before adding a new target system, ensure:

1. **Bastion Host (192.168.0.12)** is configured with:
   - `jump` user created
   - `/home/jump/.ssh/target_key` present
   - `/home/jump/.ssh/config` configured
   - SSH service running

2. **Collector (192.168.0.13)** has:
   - `~/.ssh/bastion_key` for bastion authentication
   - `~/.ssh/target_key` for target authentication
   - `~/.ssh/config` with bastion ProxyJump settings
   - SSH access to bastion verified

3. **New Target System** needs:
   - SSH service installed and running
   - Network connectivity to bastion and collector
   - `rvce` user (or specify different username)

## Step 1: Prepare the Target System

### 1.1 Start SSH Service

On the new target system (e.g., 192.168.0.10):

```bash
sudo systemctl start ssh
sudo systemctl enable ssh  # Optional: enable on boot
```

Verify SSH is running:

```bash
sudo systemctl status ssh
```

### 1.2 Create SSH Directory

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
```

### 1.3 Add Bastion's Target Public Key

Add the target public key to authorized_keys. The key is:

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILtfJLWEjSpjgmQM5Aui27hyQsY1liZdPdPPay14+miS bastion-to-targets
```

Run this command on the target system:

```bash
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILtfJLWEjSpjgmQM5Aui27hyQsY1liZdPdPPay14+miS bastion-to-targets" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

## Step 2: Verify Bastion Connection

From the **bastion host (0.12)**, test the connection to the new target:

```bash
sudo -u jump ssh rvce@192.168.0.10 hostname
```

Expected output: The hostname of the target system

If this fails:
- Verify SSH is running on target: `sudo systemctl status ssh`
- Check firewall: `sudo ufw status` (if using UFW)
- Verify public key is in `~/.ssh/authorized_keys`

## Step 3: Update Collector SSH Configuration

### 3.1 Add New Target to SSH Config

On the **collector (0.13)**, edit `~/.ssh/config`:

```bash
nano ~/.ssh/config
```

Add the new target (replace `192.168.0.10` with the actual IP):

```
Host 192.168.0.10
    User rvce
    ProxyJump bastion
    IdentityFile ~/.ssh/target_key
    StrictHostKeyChecking accept-new
```

Save and exit (Ctrl+X, then Y, then Enter in nano).

Set correct permissions:

```bash
chmod 600 ~/.ssh/config
```

### 3.2 Alternatively, Update Existing Config

If you already have multiple targets in one Host line, update it:

```
Host 192.168.0.10 192.168.0.11 192.168.0.12
    User rvce
    ProxyJump bastion
    IdentityFile ~/.ssh/target_key
    StrictHostKeyChecking accept-new
```

## Step 4: Test End-to-End Connection

### 4.1 Test from Collector

From the **collector (0.13)**:

```bash
ssh 192.168.0.10 hostname
```

Expected output: The hostname of the target system

### 4.2 Test with Verbose Output (if issues)

```bash
ssh -vvv 192.168.0.10 hostname
```

This shows detailed connection steps and helps diagnose issues.

## Step 5: Collect Metrics

### 5.1 Quick Metrics Test

On the **collector**, test metrics collection:

```bash
cd ~/Desktop/Projects/optilab-smart-lab-utilization/collector
ssh 192.168.0.10 'bash -s' < metrics_collector.sh
```

Expected output: JSON metrics data

### 5.2 Example Output

```json
{
  "timestamp": "2026-01-20T06:14:00Z",
  "hostname": "rvce-ThinkCentre-neo-50t-Gen-3",
  "uptime_seconds": 1627,
  "logged_in_users": 2,
  "cpu_percent": 2.11,
  "cpu_temperature": 27.80,
  "ram_percent": 16.85,
  "disk_percent": 10,
  "disk_read_mbps": 0.53,
  "disk_write_mbps": 6.84,
  "network_sent_mbps": 0.00,
  "network_recv_mbps": 0.00,
  "gpu_percent": null,
  "gpu_memory_used_gb": null,
  "gpu_temperature": null
}
```

### 5.3 Run Full SSH Collection Script

If you have SSH collection scripts set up:

```bash
cd ~/Desktop/Projects/optilab-smart-lab-utilization/collector
SSH_USER=rvce SSH_KEY=~/.ssh/target_key ./ssh_script.sh --single 192.168.0.10
```

## Troubleshooting

### Connection Refused

**Error:** `Connection refused` or `Connection timed out`

**Solution:**
- Verify SSH is running: `sudo systemctl status ssh`
- Check firewall rules: `sudo ufw status`
- Allow SSH through firewall: `sudo ufw allow 22/tcp`

### Permission Denied (publickey)

**Error:** `Permission denied (publickey)`

**Solution:**
- Verify target key is in `~/.ssh/authorized_keys`:
  ```bash
  cat ~/.ssh/authorized_keys | grep bastion-to-targets
  ```
- Verify file permissions:
  ```bash
  ls -la ~/.ssh/authorized_keys  # Should be -rw------- (600)
  ls -la ~/.ssh                  # Should be drwx------ (700)
  ```

### Bastion Connection Issues

**Error:** `jump@192.168.0.12: Permission denied`

**Solution:**
- Verify bastion key exists on collector:
  ```bash
  ls -la ~/.ssh/bastion_key
  ```
- Test direct bastion connection:
  ```bash
  ssh -i ~/.ssh/bastion_key jump@192.168.0.12 "echo test"
  ```
- Check bastion's authorized_keys:
  ```bash
  sudo cat /home/jump/.ssh/authorized_keys
  ```

### SSH Config Issues

**Error:** `Bad configuration option` or config not being applied

**Solution:**
- Verify SSH config syntax:
  ```bash
  ssh -G 192.168.0.10 | head -20
  ```
- Check for typos in config file (spacing, capitalization)
- Ensure correct permissions: `chmod 600 ~/.ssh/config`

## Verification Checklist

Before considering the setup complete:

- [ ] SSH service running on target: `sudo systemctl status ssh`
- [ ] Target public key in `~/.ssh/authorized_keys` on target
- [ ] Bastion can SSH to target: `sudo -u jump ssh rvce@<IP> hostname`
- [ ] Collector SSH config includes target
- [ ] Collector can SSH to target: `ssh <IP> hostname`
- [ ] Metrics collection works: `ssh <IP> 'bash -s' < metrics_collector.sh`

## Quick Reference: Adding Multiple Systems

**For adding 192.168.0.10 and 192.168.0.11:**

Collector SSH config (`~/.ssh/config`):

```
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
```

Then test both:

```bash
ssh 192.168.0.10 hostname
ssh 192.168.0.11 hostname
```

## Additional Resources

- **BASTION_DEPLOYMENT_LOG.md** - Detailed deployment history and commands
- **collector/bastion_config.sh** - Bastion configuration variables
- **collector/metrics_collector.sh** - Metrics collection script
- **scripts/get_system_details.sh** - System information collector

## Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review BASTION_DEPLOYMENT_LOG.md for detailed setup history
3. Test each connection step individually
4. Use verbose SSH output: `ssh -vvv <IP> hostname`

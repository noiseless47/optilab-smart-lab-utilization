# Setting Up This System as Bastion Host

## Quick Setup (5 Minutes)

### Step 1: Run the Setup Script

```bash
sudo ./bastion_host_setup.sh
```

The script will ask you for:
- **Bastion username** (default: `jump`) - User for SSH connections
- **SSH port** (default: `22`) - Port for SSH service
- **Collector server IP** - IP address of your OptiLab collector server
- **Target network CIDR** - Network range of lab computers (e.g., `10.30.0.0/16`)

### Step 2: What the Script Does

The automated setup configures:

✅ **SSH Server** - Hardened configuration with key-only authentication  
✅ **Bastion User** - Dedicated user account for jump host access  
✅ **Firewall (UFW)** - Only allows collector → bastion → targets  
✅ **Fail2ban** - Blocks brute force SSH attempts  
✅ **Audit Logging** - Tracks all SSH access and authentication  
✅ **Security Hardening** - Disables password auth, root login, etc.

### Step 3: Add SSH Keys

After setup completes, run these commands:

#### On Collector Server:
```bash
# Generate bastion key (if not exists)
ssh-keygen -t ed25519 -f ~/.ssh/bastion_key -C "optilab-bastion"

# Copy to bastion (replace IP and port)
ssh-copy-id -i ~/.ssh/bastion_key.pub -p 22 jump@<BASTION-IP>

# Test connection
ssh -i ~/.ssh/bastion_key -p 22 jump@<BASTION-IP>
```

#### On Bastion Server (this system):
```bash
# Generate key for target systems
sudo -u jump ssh-keygen -t ed25519 -f /home/jump/.ssh/target_key -C "bastion-to-targets"

# Copy to target systems (repeat for each lab computer)
sudo -u jump ssh-copy-id -i /home/jump/.ssh/target_key.pub admin@10.30.5.10
sudo -u jump ssh-copy-id -i /home/jump/.ssh/target_key.pub admin@10.30.5.11
# ... etc

# Or use a loop for multiple targets
for ip in 10.30.5.{10..20}; do
    sudo -u jump ssh-copy-id -i /home/jump/.ssh/target_key.pub admin@$ip
done
```

### Step 4: Test End-to-End Connection

From collector server:
```bash
# Test ProxyJump (should work)
ssh -i ~/.ssh/bastion_key \
    -J jump@<BASTION-IP>:22 \
    admin@10.30.5.10 \
    "hostname"

# If successful, you'll see the target hostname
```

### Step 5: Update Collector Configuration

On collector server, edit `collector/bastion_config.sh`:

```bash
BASTION_ENABLED="true"
BASTION_HOST="<BASTION-IP>"      # This server's IP
BASTION_PORT="22"                # Or custom port
BASTION_USER="jump"              # Or custom username
BASTION_KEY="$HOME/.ssh/bastion_key"
```

### Step 6: Run Collection

```bash
# Test with single system
./collector/ssh_script.sh --single 10.30.5.10

# Collect from all systems
./collector/ssh_script.sh --all
```

---

## Architecture After Setup

```
Collector Server ──SSH:22──▶ Bastion (This System) ──SSH:22──▶ Target Labs
(OptiLab)                    (Jump Host)                       (10.30.x.x)

• Firewall blocks all except collector
• All connections logged
• No password authentication
• Keys required at each hop
```

---

## Monitoring Commands

After setup, use these commands to monitor bastion:

```bash
# View live SSH connections
sudo tail -f /var/log/auth.log

# Check who's logged in
who

# View audit logs for SSH access
sudo ausearch -k ssh_access

# Check fail2ban status
sudo fail2ban-client status sshd

# View firewall rules
sudo ufw status verbose

# Check active SSH connections
ss -tn | grep :22
```

---

## Security Features Enabled

### SSH Hardening
- ✅ Password authentication disabled
- ✅ Root login disabled
- ✅ Only bastion user allowed
- ✅ Strong key exchange algorithms
- ✅ Connection timeouts configured
- ✅ Max 3 authentication attempts

### Firewall (UFW)
- ✅ Default deny incoming
- ✅ Only collector IP allowed to SSH port
- ✅ Only target network allowed outbound SSH
- ✅ All other traffic blocked

### Fail2ban
- ✅ Ban after 3 failed SSH attempts
- ✅ Ban duration: 2 hours
- ✅ Monitor window: 10 minutes

### Audit Logging
- ✅ All SSH access logged
- ✅ Configuration changes tracked
- ✅ User authentication monitored
- ✅ SSH key changes recorded

---

## Troubleshooting

### Cannot SSH to Bastion

**Problem:** Connection refused or timeout

**Solutions:**
```bash
# Check SSH service is running
sudo systemctl status sshd

# Check firewall allows your IP
sudo ufw status

# Add your IP if needed
sudo ufw allow from YOUR_IP to any port 22

# Check SSH is listening
sudo ss -tlnp | grep ssh
```

### Cannot Reach Targets from Bastion

**Problem:** Can SSH to bastion but not through to targets

**Solutions:**
```bash
# Test direct connection from bastion
sudo -u jump ssh admin@10.30.5.10

# Check routing
ip route

# Check firewall allows outbound
sudo ufw status | grep 10.30

# Verify target key is in place
sudo -u jump cat ~/.ssh/target_key.pub
```

### Locked Out After Setup

**Problem:** Can't login after running setup script

**Solutions:**
```bash
# From console or physical access:
# 1. Login as another sudo user
# 2. Or reboot to recovery mode
# 3. Check SSH config
sudo nano /etc/ssh/sshd_config.d/bastion.conf

# 4. Temporarily allow password auth (emergency only)
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config.d/bastion.conf
sudo systemctl restart sshd
```

---

## Configuration Files

All configuration files created:

```
/etc/ssh/sshd_config.d/bastion.conf    # SSH configuration
/etc/ssh/bastion_banner                 # SSH login banner
/etc/fail2ban/jail.local                # Fail2ban rules
/etc/audit/rules.d/bastion.rules        # Audit rules
/home/jump/.ssh/config                  # SSH client config
/root/bastion_setup_info.txt            # Setup information
```

---

## Reverting Changes

If you need to undo the setup:

```bash
# Restore original SSH config
sudo cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config
sudo rm /etc/ssh/sshd_config.d/bastion.conf
sudo systemctl restart sshd

# Reset firewall
sudo ufw --force reset
sudo ufw disable

# Stop fail2ban
sudo systemctl stop fail2ban
sudo systemctl disable fail2ban

# Remove bastion user (careful!)
sudo userdel -r jump
```

---

## Next Steps

After bastion is configured:

1. ✅ Run automated setup script
2. ✅ Add SSH keys (collector → bastion → targets)
3. ✅ Test connections end-to-end
4. ✅ Update collector's bastion_config.sh
5. ✅ Run metrics collection with bastion
6. ✅ Monitor logs for issues
7. ✅ Document bastion IP/credentials

---

## Support

For issues:
- Check `/root/bastion_setup_info.txt` for configuration details
- Review logs: `sudo tail -f /var/log/auth.log`
- See main documentation: `docs/BASTION_HOST_SETUP.md`

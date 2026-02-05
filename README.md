# NixOS Homelab Configuration

Self-hosted services with VPN access, monitoring, and AI capabilities.

**Status**: Active development. Core infrastructure (containerization, secrets management, monitoring) is stable and operational. Adding new services and improvements as needed.

## Required Configuration Changes

Before deploying, you MUST customize the following files for your environment:

### 1. Hardware Configuration

**File:** `modules/system/hardware/hardware-configuration.nix`

```bash
# Get your disk UUIDs
lsblk -f

# Get your hardware details (if installing fresh)
nixos-generate-config --show-hardware-config
```

Update:

- All filesystem UUIDs to match your disk setup
- Boot loader configuration (UEFI vs BIOS)
- CPU microcode (AMD vs Intel)
- Any hardware-specific modules
- Add custom mount points (e.g., `/mnt/storage`) to fileSystems section if needed

### 2. Main Configuration File

**File:** `config.nix`

This is your single source of truth. Update:

**User Settings:**

- `user.gitName` - Your Git commit name
- `ssh.authorizedKeys` - Your SSH public keys (REQUIRED for access)

**Generate SSH Keys** (if you don't have them):

```bash
# Standard SSH key for server access
ssh-keygen -t ed25519 -f ~/.ssh/server -C "server-access"

# FIDO2/U2F hardware security key (YubiKey, etc.) - most secure, OpenSSH format
# Creates key type: sk-ssh-ed25519@openssh.com
ssh-keygen -t ed25519-sk -f ~/.ssh/server_sk -C "server-primary-key"

# Backup FIDO2 key (use a second hardware key)
ssh-keygen -t ed25519-sk -f ~/.ssh/server_sk_backup -C "server-backup-key"

# Display your public key to add to config.nix
cat ~/.ssh/server_sk.pub
```

**Network Settings:**

```bash
# Find your server's LAN IP
ip addr show | grep "inet " | grep -v 127.0.0.1
```

- `network.server.localIp` - Your server's LAN IP (e.g., `192.168.4.105`)
- `network.server.lanNetwork` - Your LAN subnet (e.g., `192.168.4.0/24`)
- `network.server.vpnIp` - VPN IP for server (default: `10.0.0.1`)
- `network.server.vpnNetwork` - VPN subnet (default: `10.0.0.0/24`)

**WireGuard VPN (Optional):**

- `network.wireguard.enable` - Toggle VPN on/off (default: `true`)
- When enabled, set `domain-vpn` in secrets.yaml to your IP:port
  - LAN testing: `YOUR_LOCAL_IP:51820`
  - Remote access: `YOUR_PUBLIC_IP:51820` (requires port forwarding)

**Nginx Configuration:**

- `nginx.mode` - Choose reverse proxy mode:
  - `"ip-ports"` - Access via server IP with different ports (no DNS setup needed)
    - Example: `https://192.168.1.100:2283`, `https://192.168.1.100:8222`
    - Works immediately, just accept browser warnings for self-signed certs
  - `"domain-names"` - Access via friendly .local domains on port 443
    - Example: `https://immich.local`, `https://vault.local`
    - Requires Pi-hole DNS (configure router DHCP or per-device)
    - Also uses self-signed certs (same browser warnings)

Both modes use HTTPS with self-signed certificates. Trust the cert or accept browser warnings.

**Monitoring Alerts:**

- Discord webhook alerts enabled
- Requires `discord-webhook-url` in Vault secrets

### 3. SOPS Secrets

**File:** `secrets.yaml`

Generate age key:

```bash
# Generate age key for SOPS
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

Add your age public key to `.sops.yaml`, then create `secrets.yaml` with:

**Required Secrets:**

- `wireguard-private-key` - Generate: `wg genkey` (if VPN enabled)
- `domain-vpn` - Your server IP and port (e.g., `192.168.1.100:51820` or `YOUR_PUBLIC_IP:51820`)
- `vault-root-token` - Set after Vault init
- `vault-recovery-keys` - Set after Vault init
- `discord-webhook-url` - For monitoring alerts

### 4. Storage Configuration (If Using HDD Pool)

**File:** `modules/storage/hdd-pool.nix`

**Get disk UUIDs:**

```bash
# Method 1: List all block devices with filesystems
lsblk -f

# Method 2: Get UUID for specific device
blkid /dev/sda1

# Method 3: List all UUIDs
ls -l /dev/disk/by-uuid/

# Method 4: After formatting with BTRFS
mkfs.btrfs -L "HDD1" /dev/sda1
blkid /dev/sda1 | grep -oP 'UUID="\K[^"]+'

# Verify mount will work before adding to config
mount /dev/disk/by-uuid/YOUR-UUID-HERE /mnt/test
```

**Use filesystem UUID, not partition UUID.** Update all UUIDs in `hdd-pool.nix`.

## Security

- SSH keys in `config.nix` are the only way in. Password auth is disabled.
- Back up your SOPS age key (`~/.config/sops/age/keys.txt`).
- All secrets are encrypted with SOPS or stored in Vault - safe to commit configuration to git.

`<SERVER_IP>` = your server's LAN IP from `config.nix`

## Table of Contents

- [Quick Start](#quick-start)
- [Documentation](#documentation)
- [Services](#services)
- [Network Access](#network-access)
  - [VPN Setup](#vpn-setup)
  - [Local Network Access](#local-network-access)
  - [DNS Configuration](#dns-configuration)
- [Initial Setup](#initial-setup)
- [Service Configuration](#service-configuration)
- [Security](#security)
- [Maintenance](#maintenance)

---

## Quick Start

```bash
# Deploy configuration
nix run .#deploy

# View service status
systemctl status <service-name>

# Check logs
journalctl -u <service-name> -f
```

---

## Documentation

Additional documentation for specific components:

- Service configuration details in respective module files
- Vault setup and policy management scripts in `modules/system-services/vault/`
- Monitoring configuration in `modules/system-services/monitoring/`

**Secrets Management**: SOPS (encrypted in git) → Vault (runtime) → Containers

---

## Services

### Container Services

| Service         | Port     | VPN | LAN | Description                   |
| --------------- | -------- | --- | --- | ----------------------------- |
| Immich          | 2283     | ✓   | ✓   | Photo management              |
| Vaultwarden     | 8222     | ✓   | ✗   | Password manager (VPN-only)   |
| HashiCorp Vault | 8200     | ✓   | ✗   | Secrets management (VPN-only) |
| Portainer       | 9000     | ✓   | ✓   | Container management          |
| Gitea           | 3000     | ✓   | ✓   | Git server                    |
| Jellyfin        | 8096     | ✓   | ✓   | Media server                  |
| n8n             | 5678     | ✓   | ✓   | Workflow automation           |
| Memos           | 5230     | ✓   | ✓   | Note-taking                   |
| Linkwarden      | 3500     | ✓   | ✓   | Link management               |
| Open WebUI      | 8088     | ✓   | ✓   | AI interface (Ollama)         |
| Pi-hole         | 53, 8080 | ✓   | ✓   | DNS + ad blocking             |
| Restic Server   | 8001     | ✓   | ✓   | Backup repository server      |

### Monitoring Stack

| Service       | Port | Access                       | Description        |
| ------------- | ---- | ---------------------------- | ------------------ |
| Grafana       | 3030 | VPN/LAN via monitoring.local | Dashboards         |
| Prometheus    | 9090 | Internal                     | Metrics collection |
| Loki          | 3100 | Internal                     | Log aggregation    |
| Promtail      | 3031 | Internal                     | Log shipping       |
| Alertmanager  | 9093 | Internal                     | Alert routing      |
| Node Exporter | 9100 | Internal                     | System metrics     |

### System Services

- PostgreSQL - Database backend
- HashiCorp Vault - Secret management with auto-unsealing
- Ollama - Local LLM inference with CUDA acceleration
- fail2ban - Brute-force protection (SSH, Minecraft, exploits)
- WireGuard VPN - Secure remote access

### Optional Services

**Samba Network File Sharing** (`modules/storage/network-storage.nix`)

Untested. Shares `/mnt/storage` and `/mnt/ssd` via SMB/CIFS.

---

## Network Access

### Access Methods

Configured in `config.nix` via `nginx.mode`:

1. **IP with ports** (`nginx.mode = "ip-ports"`):
   - Access: `https://<SERVER_IP>:2283`, `https://<SERVER_IP>:8222`, etc.
   - No DNS setup needed - works immediately
   - Each service gets its own port
   - Self-signed HTTPS certs (accept browser warnings or trust cert)

2. **Domain names** (`nginx.mode = "domain-names"`):
   - Access: `https://immich.local`, `https://vault.local`, etc.
   - Requires Pi-hole DNS (router DHCP or per-device configuration)
   - All services on port 443 with friendly domain names
   - Self-signed HTTPS certs (same as ip-ports mode)

Both modes use HTTPS with self-signed certificates. Choose ip-ports for simplicity or domain-names for convenience.

**VPN access**: Works with either nginx mode when WireGuard is enabled

### VPN Setup

**Server**: Configured on `10.0.0.1`, UDP port 51820

**Add a new peer**:

**Using doas wg-add-peer (Recommended):**

```bash
# Run the helper script
doas wg-add-peer

# It will:
# 1. Generate client keys
# 2. Show you the peer config to ADD to modules/network/wireguard.nix
# 3. Wait for you to manually add it and deploy
# 4. Display a QR code for the client to scan
```

Script shows you the config - you still need to add it to wireguard.nix manually and deploy.

**Client configuration example**:

```ini
[Interface]
PrivateKey = <client-private-key>
Address = 10.0.0.X/32
DNS = 10.0.0.1

[Peer]
PublicKey = <server-public-key>
Endpoint = <server-public-ip>:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
```

### Port Forwarding (Router Configuration)

To access services from the internet, configure port forwarding on your router:

**Required Ports:**

- **51820 UDP** → WireGuard VPN (already configured in `networking.nix`)
- **25565 TCP** → Minecraft server (optional, if hosting Minecraft)

**How to set up port forwarding:**

1. Log into your router's admin interface (usually `192.168.1.1` or `192.168.0.1`)
2. Find "Port Forwarding", "Virtual Server", or "NAT" settings (name varies by router)
3. Create new forwarding rules:

   **WireGuard VPN:**
   - External Port: `51820`
   - Internal IP: Your server's LAN IP (from `config.nix`)
   - Internal Port: `51820`
   - Protocol: **UDP**

   **Minecraft (Optional):**
   - External Port: `25565`
   - Internal IP: Your server's LAN IP
   - Internal Port: `25565`
   - Protocol: **TCP**

4. Save and test connection from outside your network

Only forward what you need. VPN gives you everything without exposing ports.

### Local Network Access

Services are accessible on LAN at `<SERVER_IP>`.

**Mode 1: IP with Ports** (`nginx.mode = "ip-ports"`):

```
https://<SERVER_IP>:2283  # Immich
https://<SERVER_IP>:8222  # Vaultwarden
https://<SERVER_IP>:9000  # Portainer
https://<SERVER_IP>:3000  # Gitea/Forgejo
https://<SERVER_IP>:8096  # Jellyfin
https://<SERVER_IP>:5678  # n8n
https://<SERVER_IP>:8088  # Open WebUI
```

No DNS setup needed. Self-signed HTTPS certs (accept browser warnings).

**Mode 2: Domain Names** (`nginx.mode = "domain-names"`):

```
https://immich.local
https://vault.local
https://portainer.local
https://gitea.local (or forgejo.local)
https://jellyfin.local
https://n8n.local
https://ai.local
```

Requires DNS configuration (see below). Self-signed HTTPS certs (same warnings).

### DNS Configuration

**Only required for `nginx.mode = "domain-names"`**

To use `.local` domain names, configure DNS resolution:

**Option A: Router DHCP** (recommended - affects all devices)

1. Access router admin panel
2. Navigate to DHCP settings
3. Set Primary DNS: `<SERVER_IP>`
4. Set Secondary DNS: `8.8.8.8` or `1.1.1.1` (fallback)
5. Save and reboot devices to get new DNS

**Option B: Per-device DNS** (manual configuration)

_Linux/macOS (systemd-resolved)_:

```bash
# Edit /etc/systemd/resolved.conf
DNS=<SERVER_IP>
FallbackDNS=8.8.8.8

sudo systemctl restart systemd-resolved
```

_macOS (Network Preferences)_:

```
System Preferences → Network → Advanced → DNS
Add: <SERVER_IP>
```

_Windows (Network Settings)_:

```
Settings → Network → Adapter Settings → Properties → IPv4
Preferred DNS: <SERVER_IP>
Alternate DNS: 8.8.8.8
```

_Android/iOS_:

```
WiFi Settings → Modify Network → Advanced → DNS
Set to: <SERVER_IP>
```

**Option C: /etc/hosts** (no DNS change needed)

Add to `/etc/hosts` (Linux/Mac) or `C:\Windows\System32\drivers\etc\hosts` (Windows):

```
<SERVER_IP> immich.local
<SERVER_IP> jellyfin.local
<SERVER_IP> gitea.local
<SERVER_IP> portainer.local
<SERVER_IP> n8n.local
<SERVER_IP> memos.local
<SERVER_IP> links.local
<SERVER_IP> ai.local
10.0.0.1 vault.local
10.0.0.1 hashi-vault.local
10.0.0.1 monitoring.local
```

VPN-only: vault, hashi-vault, monitoring

### SSL Certificates

Both nginx modes use self-signed certificates. Browsers will show security warnings.

**Options:**

1. Accept the browser warning each time (easiest)
2. Trust the certificate once on each device (removes warnings)

**To trust the certificate** (optional):

```bash
# Download from server
scp server:/var/lib/nginx/ssl/local-domains.crt ~/

# Linux
sudo cp local-domains.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates

# macOS
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain local-domains.crt

# Windows
# Import into "Trusted Root Certification Authorities" via certmgr.msc
```

Or just accept browser warnings.

---

## Initial Setup

### 1. Vault Configuration

After Vault is initialized and unsealed:

```bash
# Run the vault-setup-policies script
doas vault-setup-policies

# This will:
# 1. Enable AppRole auth
# 2. Configure PostgreSQL database backend
# 3. Create policies for all containers
# 4. Generate AppRole credentials (role_id and secret_id)
# 5. Display credentials to copy to secrets.yaml

# Copy the output credentials, then:
sops secrets.yaml
# Paste the credentials into the appropriate fields

# Deploy the updated secrets
sudo nixos-rebuild switch
```

Run this script again if you add new containers or need to rotate credentials.

### 2. Vaultwarden Admin Token

Generate and store admin token:

```bash
# Generate token hash
echo -n 'your-secure-password' | argon2 "$(openssl rand -base64 32)" -e -id -k 65536 -t 3 -p 4

# Store in Vault
doas podman exec -e VAULT_TOKEN="$(doas cat /run/secrets/vault-root-token)" vault \
  vault kv put -mount=secret vaultwarden/admin-token token='<generated-hash>'
```

### 3. AI Services

Download Ollama models:

```bash
ollama pull llama3.2      # Fast chat (3B, ~4GB RAM)
ollama pull mistral       # Balanced (7B, ~8GB RAM)
ollama pull codellama     # Code-focused (7B, ~8GB RAM)
```

Access at `https://ai.local`, create account on first visit.

### 4. Pi-hole

Access web interface:

- URL: `http://<SERVER_IP>:8080/admin`
- Password: Stored in Vault (`secret/pihole/webpassword`)

---

## Service Configuration

Configure services through their web interfaces:

### Vaultwarden (Password Manager)

1. Access: `https://vault.local` (VPN only)
2. Create your account (first user becomes admin)
3. Admin panel: `https://vault.local/admin` (use token from Initial Setup step 2)
4. Configure:
   - Two-factor authentication (Settings → Security)
   - Master password policy (Admin → Settings)

### Immich (Photos)

1. Access: `https://immich.local`
2. Create admin account on first visit
3. Configure:
   - Storage template (Administration → Settings → Storage Template)
   - Machine learning (Administration → Settings → Machine Learning)
   - External library paths if needed
4. Mobile app: Download from app store, connect to `https://immich.local`

### Jellyfin (Media)

1. Access: `https://jellyfin.local`
2. Run initial setup wizard:
   - Set admin credentials
   - Add media libraries (paths: `/mnt/storage/media/*`)
   - Configure metadata providers
3. Hardware acceleration:
   - NVIDIA: Already configured (see `modules/system/hardware/nvidia.nix`)
   - AMD: Update `modules/system/hardware/hardware-configuration.nix` to enable AMD GPU drivers:
     ```nix
     # Add to hardware-configuration.nix
     boot.initrd.kernelModules = [ "amdgpu" ];
     services.xserver.videoDrivers = [ "amdgpu" ];
     hardware.opengl.extraPackages = with pkgs; [ amdvlk rocm-opencl-icd ];
     ```

### Gitea (Git Server)

1. Access: `https://gitea.local`
2. Initial setup runs automatically
3. Create admin account
4. Configure:
   - SSH keys (Settings → SSH/GPG Keys)
   - Repository defaults (Site Administration → Configuration)

### n8n (Workflow Automation)

1. Access: `https://n8n.local`
2. Create owner account on first visit
3. Configure:
   - Credentials (Settings → Credentials)
   - Environment variables if needed

### Portainer (Container Management)

1. Access: `https://portainer.local`
2. Create admin account on first visit
3. Connect to local environment (automatically detected)
4. View containers, logs, stats

### Pi-hole (DNS/Ad Blocking)

1. Access: `http://<SERVER_IP>:8080/admin`
2. Login with password from Vault (`secret/pihole/webpassword`)
3. Configure:
   - Blocklists (Adlists → Add common lists)
   - Local DNS records (Local DNS → DNS Records)
   - DHCP if desired (Settings → DHCP)

### Open WebUI (AI Chat)

1. Access: `https://ai.local`
2. Create account on first visit (local only, no external auth)
3. Select model from dropdown
4. Configure:
   - Model parameters (Settings → Models)
   - System prompts (Settings → Prompts)

### Grafana (Monitoring)

1. Access: `https://monitoring.local` (VPN only)
2. Login: `admin` / `admin` (change on first login)
3. Pre-configured:
   - Data sources (Prometheus, Loki)
   - Dashboards (system metrics, containers, alerts)
4. Customize dashboards as needed

### Memos (Notes)

1. Access: `https://memos.local`
2. Create account on first visit
3. Start taking notes with markdown support

### Linkwarden (Link Management)

1. Access: `https://links.local`
2. Create account on first visit
3. Configure browser extension for easy saving

### Minecraft Server

**Access:**

- Local/LAN: `<SERVER_IP>:25565`
- Internet: `<YOUR_PUBLIC_IP>:25565` (requires port forwarding - see Network Access section)

**Running Commands:**

Switch to minecraft user and use `mc-send-to-console`:

```bash
# Method 1: Using machinectl (from any user with sudo)
machinectl shell minecraft@.host
podman exec minecraft mc-send-to-console "say Hello World"
podman exec minecraft mc-send-to-console "whitelist add PlayerName"

# Method 2: Direct sudo
sudo -u minecraft podman exec minecraft mc-send-to-console "list"
```

**View Logs:**

```bash
# As minecraft user
journalctl --user -u podman-minecraft -f

# Direct file access
tail -f /mnt/ssd/minecraft/logs/latest.log
```

**Whitelist Management:**

- File location: `/mnt/ssd/minecraft/whitelist.json`
- Add via command: `mc-send-to-console "whitelist add PlayerName"`
- Enforce: Already enabled in configuration

---

## Security

### Firewall

**Public (WAN)**:

- TCP 25565 (Minecraft)
- UDP 51820 (WireGuard)

**VPN (wg0)**:

- TCP 53, 8080, 8001, 3030
- UDP 53

**LAN**:

- All container ports (via docker bridge)
- HTTPS 443 (nginx reverse proxy)

### fail2ban

Active jails:

- **sshd**: Max 3 attempts in 10min, 1hr ban
- **minecraft**: Max 5 attempts in 5min, 30min ban
- **minecraft-exploit**: Log4Shell/JNDI detection, permanent ban

### Secrets Management

All secrets managed via:

- **SOPS**: Encrypted at rest in git
- **HashiCorp Vault**: Runtime secret distribution
- **Vault Agent**: Automatic injection to containers

Never commit plaintext secrets.

### VPN-Only Services

These services ONLY accessible via VPN:

- Vaultwarden (password manager)
- HashiCorp Vault UI
- Grafana (monitoring)

Nginx configured to listen only on `10.0.0.1` for these services.

---

## Technical Implementation Notes

### Network: Why 127.0.0.1 not localhost

Server uses `127.0.0.1` everywhere instead of `localhost`. Why? Testing showed `localhost` caused failures (DNS timing, IPv4/IPv6 issues). Explicit IP fixes it.

All Nix files use `${localhost.ip}` from `config.nix`. Don't change it.

---

## Maintenance

### Update System

```bash
# Update flake inputs
nix flake update

# Rebuild and deploy
nix run .#deploy

# Reboot if kernel updated
sudo reboot
```

### Container Management

```bash
# View running containers
podman ps

# View logs
podman logs -f <container-name>

# Restart service
systemctl restart podman-<service-name>

# Update container image
podman pull <image-name>
systemctl restart podman-<service-name>
```

### Backup

#### Server Setup

Restic REST server runs on port `8001` for backing up client machines to `/mnt/storage/restic/data`.

**Configure authentication** (add to Vault):

```bash
# Generate htpasswd hash (use SHA format, NOT bcrypt)
nix-shell -p apacheHttpd --run "htpasswd -nbs username YourPassword"

# Add output to Vault secret: restic-htpasswd
# Example: username:{SHA}base64hash

# If you need to URL-encode the password for client usage:
echo -n "YourPassword" | jq -sRr '@uri'
```

Restic needs SHA format (`{SHA}...`), not bcrypt. Use `-s` flag with htpasswd.

**Retrieve password from Vault** (if stored there):

```bash
doas podman exec -e VAULT_TOKEN="$(doas cat /run/secrets/vault-root-token)" vault \
  vault kv get -mount=secret restic/password
```

#### Client Setup (Your PC)

**1. Install Restic:**

```bash
# Linux (Debian/Ubuntu)
sudo apt install restic

# Arch Linux
sudo pacman -S restic

# macOS
brew install restic

# Windows (Scoop)
scoop install restic
```

**2. Configure Environment:**

```bash
# Linux/macOS - add to ~/.bashrc or ~/.zshrc
export RESTIC_REPOSITORY="rest:http://username:password@<SERVER_IP>:8001/laptop"
export RESTIC_PASSWORD_FILE="$HOME/.restic-password"

# Create password file (for repository encryption, separate from auth)
echo "YourRepositoryEncryptionPassword" > ~/.restic-password
chmod 600 ~/.restic-password
```

**Windows PowerShell:**

```powershell
$env:RESTIC_REPOSITORY="rest:http://username:password@<SERVER_IP>:8001/laptop"
"YourRepositoryEncryptionPassword" | Out-File $env:USERPROFILE\.restic-password
```

**3. Initialize Repository:**

```bash
restic init
```

**4. Backup Important Data:**

```bash
# Backup specific folders
restic backup ~/Documents ~/Pictures ~/Projects \
  --exclude="node_modules" \
  --exclude="*.tmp" \
  --exclude=".cache"

# List snapshots
restic snapshots

# Check repository health
restic check
```

**5. Restore Data:**

```bash
# List files in latest snapshot
restic ls latest

# Test restore in temp location first
mkdir ~/restore-test
restic restore latest --target ~/restore-test

# Restore specific files
restic restore latest --target ~/restore-test --include "/path/to/file"
```

**6. Automated Backups:**

Linux/macOS cron example (daily at 2 AM):

```bash
# Add to crontab (crontab -e)
0 2 * * * restic backup ~/Documents ~/Pictures ~/Projects && restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
```

**7. Server Monitoring:**

```bash
# Check server status
curl http://<SERVER_IP>:8001/

# View server logs
journalctl -u podman-restic -f
```

**Repository Naming Convention:**

- `/laptop` - Your laptop backups
- `/desktop` - Your desktop PC backups
- `/work-laptop` - Work machine backups
- Each device should use a unique repository path

**Authentication:**

Server stores username:hash. Clients use username:plaintext in URL. Server hashes and compares.

### Monitoring

Access Grafana at `https://monitoring.local` (VPN) or `https://<SERVER_IP>:3030`. Dashboards for system metrics, containers, service health, and alerts. Alerts sent via Discord webhook (configure in Vault).

### Logs

View in Grafana Loki or journalctl:

```bash
# Service logs
journalctl -u <service-name> -f

# All container logs
journalctl -u podman-* -f

# Specific time range
journalctl --since "1 hour ago"
```

---

## Troubleshooting

### Service not accessible

Check if running:

```bash
systemctl status podman-<service-name>
```

2. Verify port is listening:

   ```bash
   ss -tlnp | grep <port>
   ```

3. Test direct connection:

   ```bash
   curl http://127.0.0.1:<port>
   ```

4. Check firewall:
   ```bash
   sudo nft list ruleset | grep <port>
   ```

### DNS not resolving .local domains

1. Verify Pi-hole is running:

   ```bash
   systemctl status podman-pihole
   ```

2. Test DNS resolution:

   ```bash
   nslookup jellyfin.local <SERVER_IP>
   ```

3. Check device DNS settings:

   ```bash
   # Linux
   resolvectl status

   # macOS
   scutil --dns

   # Windows
   ipconfig /all
   ```

### VPN not connecting

1. Verify WireGuard is running:

   ```bash
   systemctl status wireguard-wg0
   sudo wg show
   ```

2. Check server is reachable:

   ```bash
   nc -vuz <server-ip> 51820
   ```

3. Verify peer configuration in `modules/network/wireguard.nix`

### Container won't start

1. Check logs:

   ```bash
   journalctl -u podman-<service-name> -n 50
   ```

2. Verify Vault secrets are accessible:

   ```bash
   ls -la /run/secrets/
   ```

3. Test container manually:
   ```bash
   podman run -it <image-name> /bin/sh
   ```

### Container network issues

If containers can't talk to each other (e.g., Immich → Redis timeout), networking state may be corrupted. Delete and reboot:

```bash
# List all containers
sudo podman ps -a

# Remove specific containers (example for Immich)
sudo podman rm -f immich immich-ml immich-redis

# Or remove all containers
sudo podman rm -f $(sudo podman ps -aq)

# Reboot to recreate everything fresh
sudo reboot
```

NixOS will recreate the containers on boot with fresh networking state.

### Immich-Friend container issues

If immich-friend rootless containers need to be cleaned up and restarted:

```bash
# Use the 'imf' alias for immich-friend shell access
# Stop all rootless podman services
imf systemctl --user stop 'podman-*.service'

# Remove all containers
imf podman rm -af

# Clean up unused images
imf podman image prune -af

# Reboot to let NixOS recreate everything
sudo reboot
```

Note: `imf` is an alias for `doas machinectl shell immich-friend@`

**DNS resolution on boot**: Rootless containers under immich-friend may fail DNS lookups on boot until the system DNS is fully initialized. The configuration includes a wait-for-dns helper that delays container startup until DNS works. If containers show DNS errors, they'll retry automatically.

---

## File Structure

```
.
├── flake.nix                    # Main flake configuration
├── modules/
│   ├── system/
│   │   └── networking.nix       # Firewall, DNS, network config
│   ├── network/
│   │   └── ... # Network modules
│   │   ├── nginx.nix            # Reverse proxy
│   │   ├── wireguard.nix        # VPN configuration
│   │   └── cloudflared.nix      # Public tunnel
│   ├── system-services/
│   │   ├── containers/          # Container definitions
│   │   ├── vault/               # Vault + policies
│   │   └── monitoring/          # Grafana, Prometheus, Loki
│   └── ai/
│       └── ollama.nix           # LLM services
└── secrets/
    └── secrets.yaml             # SOPS-encrypted secrets
```

---

## Additional Resources

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Podman Documentation](https://docs.podman.io/)
- [WireGuard Documentation](https://www.wireguard.com/quickstart/)
- [Pi-hole Documentation](https://docs.pi-hole.net/)
- [Vault Documentation](https://developer.hashicorp.com/vault/docs)
- [SOPS Documentation](https://github.com/mozilla/sops)

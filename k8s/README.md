# Kubernetes (k3s) Setup and Commands

This directory contains Kubernetes manifests for the k3s cluster running on the NixOS server.

**Status**: Production-grade k3s deployment with GitOps automation via ArgoCD. Core cluster operations, secrets management (Vault + ESO), and ingress routing are fully functional. Continuous improvements to application deployments, observability, and multi-tenancy patterns.

## Initial Configuration

**Before using these manifests**, update Git repository URLs in two places:

1. **config.nix**: `container-backend.k3s.gitops.github.repoURL = "git@github.com:YOUR_USERNAME/YOUR_REPO.git"`
2. **k8s/argocd/applicationset.yaml**: Update both `repoURL` fields to match

See main [README.md](../README.md#3-k3s-configuration-if-using-k3s) for full configuration details.

## Table of Contents

- [kubectl Setup](#kubectl-setup)
- [Accessing the Cluster](#accessing-the-cluster)
- [Common Commands](#common-commands)
- [Applications](#applications)
- [Troubleshooting](#troubleshooting)

## kubectl Setup

### On the Server (Direct Access)

If you're SSH'd into the server:

```bash
# kubectl is already available via k3s
sudo k3s kubectl get nodes

# Or use the k3s kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
```

### On Your Deploy PC (Remote Access)

#### Option 1: Copy kubeconfig and Use Directly

```bash
# Copy kubeconfig from server
ssh your-server 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/config

# IMPORTANT: Edit ~/.kube/config and change server address
# From: server: https://localhost:6443
# To:   server: https://192.168.4.105:6443  # Your server IP

# Test connection
kubectl get nodes
```

#### Option 2: SSH Tunnel (More Secure)

```bash
# Create SSH tunnel for k3s API
ssh -L 6443:localhost:6443 your-server

# In another terminal, use kubectl
# The kubeconfig can use localhost:6443
kubectl get nodes
```

#### Option 3: VPN Access

If you have WireGuard VPN configured:

```bash
# Connect to VPN
sudo wg-quick up wg0

# Use server's VPN IP in kubeconfig
# server: https://10.10.0.1:6443

kubectl get nodes
```

## Accessing the Cluster

### Network Configuration (config.nix)

The `container-backend.k3s.exposeLAN` option controls whether k3s services are accessible on your LAN:

```nix
# config.nix
container-backend.k3s = {
  exposeLAN = false;  # Default: VPN or SSH tunnel access only
  # exposeLAN = true; # Enable for direct LAN access (less secure)
};
```

**Security Recommendation**: Keep `exposeLAN = false` and use SSH tunnels or VPN for access.

### Access Methods

#### Option 1: SSH Tunnel (Recommended - Most Secure)

Create SSH tunnels to access k3s services securely:

```bash
# Tunnel multiple services at once
ssh -L 6443:localhost:6443 \    # k3s API
    -L 8300:localhost:8300 \    # K3s Vault (NodePort 8300 avoids conflict with rootful Vault on 8200)
    -L 31553:localhost:31553 \  # ArgoCD HTTP
    -L 32443:localhost:32443 \  # ArgoCD HTTPS
    admin@<SERVER_IP>

# Then access services on localhost:
# - kubectl: https://localhost:6443
# - Vault UI: http://localhost:8300 (K3s Vault via NodePort)
# - ArgoCD: http://localhost:31553 or https://localhost:32443
#
# Note: Rootful Podman Vault is on port 8200 (different Vault instance)
```

**kubectl with SSH tunnel:**

```bash
# Use this format when tunneling
kubectl --server=https://localhost:6443 --insecure-skip-tls-verify get pods -A

# Or set up kubeconfig to use localhost:6443
```

#### Option 2: LAN Access (If exposeLAN = true)

When `exposeLAN` is enabled in config.nix, services are accessible on LAN:

- **k3s API**: `https://<SERVER_IP>:6443`
- **ArgoCD**: `http://<SERVER_IP>:31553` (HTTP) or `https://<SERVER_IP>:32443` (HTTPS)
- **Vault**: `http://<SERVER_IP>:8300`

**kubectl with LAN access:**

```bash
kubectl --server=https://<SERVER_IP>:6443 --insecure-skip-tls-verify get pods -A
```

#### Option 3: VPN Access

Connect via WireGuard VPN and access via VPN IPs:

```bash
# Connect to VPN
sudo wg-quick up wg0

# Access k3s API on VPN IP
kubectl --server=https://10.10.0.1:6443 --insecure-skip-tls-verify get nodes
```

### Access via Ingress (HTTPS)

Applications exposed through nginx-ingress (via Cloudflare tunnel):

- **Immich**: `https://your-immich-domain.com`
- **Authelia**: `https://your-auth-domain.com`

## Common Commands

### Cluster Status

```bash
# Check nodes
kubectl get nodes

# Check all pods across all namespaces
kubectl get pods -A

# Check specific namespace
kubectl get pods -n immich-friend

# Check services
kubectl get svc -A

# Check ingress resources
kubectl get ingress -A
```

### Working with Applications

```bash
# View application status in ArgoCD namespace
kubectl get applications -n argocd

# Describe an application
kubectl describe application immich-friend -n argocd

# Force sync an application
kubectl patch application immich-friend -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

### Viewing Logs

```bash
# Get logs from a pod
kubectl logs -n immich-friend <pod-name>

# Follow logs
kubectl logs -n immich-friend <pod-name> -f

# Get logs from all pods with a label
kubectl logs -n immich-friend -l app=authelia --tail=50

# Get logs from previous container instance (after crash)
kubectl logs -n immich-friend <pod-name> --previous
```

### Secrets and ConfigMaps

```bash
# List secrets
kubectl get secrets -n immich-friend

# View secret contents (base64 encoded)
kubectl get secret authelia-secrets -n immich-friend -o yaml

# Decode a specific secret key
kubectl get secret authelia-secrets -n immich-friend -o jsonpath='{.data.jwt-secret}' | base64 -d

# View ExternalSecrets status
kubectl get externalsecrets -n immich-friend
kubectl describe externalsecret authelia-secrets -n immich-friend
```

### Restarting Pods

```bash
# Delete pod (will be recreated by deployment)
kubectl delete pod <pod-name> -n immich-friend

# Restart all pods with a specific label
kubectl delete pods -n immich-friend -l app=authelia

# Restart deployment (rolling restart)
kubectl rollout restart deployment/immich -n immich-friend
```

### Port Forwarding

```bash
# Forward local port to a pod
kubectl port-forward -n immich-friend pod/<pod-name> 8080:9091

# Forward to a service
kubectl port-forward -n immich-friend svc/authelia 9091:9091
```

### Debugging

```bash
# Get detailed pod information
kubectl describe pod <pod-name> -n immich-friend

# Get events (useful for troubleshooting)
kubectl get events -n immich-friend --sort-by='.lastTimestamp'

# Execute command in a pod
kubectl exec -n immich-friend <pod-name> -- ls /config

# Interactive shell in a pod
kubectl exec -it -n immich-friend <pod-name> -- /bin/sh

# Check resource usage
kubectl top nodes
kubectl top pods -n immich-friend
```

### ExternalSecrets Troubleshooting

```bash
# Check if ESO is running
kubectl get pods -n external-secrets-system

# View ESO logs
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets --tail=50

# Force refresh an ExternalSecret
kubectl annotate externalsecret authelia-secrets -n immich-friend force-sync=$(date +%s) --overwrite

# Delete and recreate (ArgoCD will recreate it)
kubectl delete externalsecret authelia-secrets -n immich-friend
```

## Applications

This cluster runs the following applications:

- **[ArgoCD](argocd/README.md)** - GitOps continuous deployment
- **[Vault](vault/README.md)** - Secrets management
- **[Immich Friend](immich-friend/README.md)** - Photo sharing application with OAuth
- **[Ingress NGINX](ingress-nginx/)** - Ingress controller for HTTPS routing
- **[Reloader](reloader/README.md)** - Automatic pod restarts on ConfigMap/Secret changes

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl describe pod <pod-name> -n <namespace>

# Common issues:
# - Image pull errors: Check image name and registry access
# - Volume mount errors: Check PVC status with `kubectl get pvc -n <namespace>`
# - Resource limits: Check node resources with `kubectl top nodes`
```

### ExternalSecrets Not Syncing

**Common Cause**: Vault is sealed after reboot.

```bash
# 1. Check if Vault is sealed
kubectl exec -n vault vault-0 -- vault status

# 2. If sealed, unseal with your 3 unseal keys
kubectl exec -n vault vault-0 -- vault operator unseal <UNSEAL_KEY_1>
kubectl exec -n vault vault-0 -- vault operator unseal <UNSEAL_KEY_2>
kubectl exec -n vault vault-0 -- vault operator unseal <UNSEAL_KEY_3>

# Alternative: Unseal via UI at http://localhost:8300 (through SSH tunnel to K3s Vault)

# 3. Force ExternalSecrets to refresh
kubectl annotate externalsecret -n immich-friend --all force-sync=$(date +%s) --overwrite

# 4. Check SecretStore connectivity
kubectl describe secretstore vault-backend -n immich-friend

# 5. If still failing, check Vault connectivity from cluster
# Uses internal cluster service port 8200 (LoadBalancer exposes externally on 8300)
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl -v http://vault.vault.svc.cluster.local:8200/v1/sys/health
```

**Note**: Vault must be unsealed after every server reboot. Save your unseal keys securely!

### Ingress Not Working

```bash
# Check ingress controller is running
kubectl get pods -n ingress-nginx

# Check ingress resource
kubectl get ingress -n immich-friend
kubectl describe ingress immich-friend-ingress -n immich-friend

# Check service endpoints
kubectl get endpoints -n immich-friend

# Test from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl http://authelia.immich-friend.svc.cluster.local:9091
```

### Application Not Available Externally

1. Check ingress: `kubectl get ingress -n <namespace>`
2. Check service: `kubectl get svc -n <namespace>`
3. Check pods: `kubectl get pods -n <namespace>`
4. Check DNS: `nslookup <your-domain>`
5. Check firewall on server: Port 443 should be open
6. Check nginx logs: `kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx`

### Services Can't Connect After Reboot

If ArgoCD or other services show connection errors like `dial tcp 10.43.x.x:xxxx: connect: connection refused` after a reboot:

```bash
# Restart k3s as the immich-friend user
machinectl shell immich-friend@ /bin/sh -c "systemctl --user restart k3s-server"

# Or restart specific pods that are having connectivity issues
kubectl delete pod <pod-name> -n <namespace>

# Wait for pods to fully restart
kubectl get pods -n <namespace> -w
```

**Cause**: k3s networking (kube-proxy/service mesh) may not fully initialize before pods start after a reboot. Restarting k3s or the affected pods resolves the issue.

## Advanced Topics

### Backing Up etcd

k3s stores cluster state in etcd. To backup:

```bash
# On the server
sudo k3s etcd-snapshot save

# Snapshots stored in: /var/lib/rancher/k3s/server/db/snapshots/
```

### Updating Applications

Applications are managed by ArgoCD and auto-sync from git. To update:

1. Update manifest in git repository
2. Commit and push
3. ArgoCD will automatically sync (or use manual sync)

```bash
# Manual sync via CLI
argocd app sync <app-name>

# Or via kubectl
kubectl patch application <app-name> -n argocd --type merge -p '{"operation":{"sync":{}}}'
```

## Security Notes

- **Keep `exposeLAN = false`**: Access k3s via SSH tunnels or VPN only
- **Vault Unsealing**: Required after every reboot - store unseal keys securely offline
- **SSH Keys**: Use FIDO2-backed SSH keys for hardware-based authentication
- **Secrets Rotation**: Regularly rotate secrets in Vault (especially after team changes)
- **Bot Protection**: nginx ingress blocks common exploit scanner paths
- **Fail2ban**: Automatically bans IPs after failed Authelia authentication attempts
- **TLS**: Always use HTTPS for external services (via Cloudflare tunnel)

For more information, see:

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [k3s Documentation](https://docs.k3s.io/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)

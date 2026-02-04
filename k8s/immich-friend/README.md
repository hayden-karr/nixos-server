# Immich Friend - Kubernetes Manifests

GitOps-managed deployment for immich-friend stack on K3s.

## Architecture

- **Namespace**: `immich-friend`
- **Secrets Management**: External Secrets Operator (ESO) syncs from Vault
- **Components**:
  - PostgreSQL (StatefulSet)
  - Redis (Deployment)
  - Authelia (Deployment with OAuth/FIDO2)
  - Immich Server (Deployment)

## Prerequisites

1. **K3s running** - Managed by NixOS
2. **Vault** - Running in `vault` namespace, initialized and unsealed
3. **External Secrets Operator** - Deployed via ArgoCD
4. **Vault configured** - Run `scripts/setup-vault.sh` to configure AppRole and secrets
5. **Kubernetes Secrets**:
   - `vault-approle` - Vault AppRole credentials (created manually from setup script output)
   - `domain-secrets` - Domain configuration for OAuth (create manually)

## Deployment

### Option 1: ArgoCD (GitOps - Recommended)

1. Commit manifests to git
2. Create ArgoCD Application:

```bash
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: immich-friend
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/YOUR_USERNAME/nixos-server-2
    targetRevision: main
    path: k8s/immich-friend
  destination:
    server: https://kubernetes.default.svc
    namespace: immich-friend
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
```

3. Push to git

### Option 2: Manual kubectl

```bash
kubectl apply -f k8s/immich-friend/
```

## Storage

**hostPath mode** (current):

- Shares storage with podman setup
- `/mnt/ssd/immich_friend/` - Config, cache, postgres
- `/mnt/storage/immich_friend/` - Media files

## Secrets Management with External Secrets Operator

External Secrets Operator (ESO) syncs secrets from Vault to Kubernetes.

### How It Works

1. **SecretStore** - Defines ESO authentication with Vault (AppRole)
2. **ExternalSecret CRDs** - Declare what secrets to sync from Vault
3. **ESO Controller** - Watches ExternalSecrets, creates/updates Kubernetes Secrets
4. **Pods** - Reference standard Kubernetes Secrets

### Setup Process

**1. Generate OAuth client secret hash**:

```bash
# Generate the hash (Authelia requires pbkdf2-sha512)
kubectl run -it --rm hash --image=authelia/authelia:latest --restart=Never -- \
  authelia crypto hash generate pbkdf2 --variant sha512 --random.length 32 --password 'your-secret'

# Copy the $pbkdf2-sha512$310000$... output
```

**2. Update Terraform configuration**:

Edit `terraform/vault/terraform.tfvars`:

```hcl
oauth_client_secret_hashed = "$pbkdf2-sha512$310000$..."
```

The hash is stored in Vault and injected into Authelia config via init container.

**3. Configure Vault with OpenTofu** (Infrastructure-as-Code):

```bash
cd terraform/vault

# Set root token (Vault address is already configured in providers.tf)
export VAULT_TOKEN="<root-token>"

# Apply configuration
tofu init
tofu apply

# Optional: Set Resend API key
tofu apply -var="resend_api_key=re_xxxxxxxxxxxx"
```

This configures AppRole, creates secrets, and outputs credentials. Vault accessible at `http://localhost:30820` via NodePort.

**4. Create the Kubernetes secret for ESO authentication**:

```bash
# Get the command from OpenTofu output
tofu output -raw kubernetes_secret_command | bash

# Or manually:
kubectl create secret generic vault-approle -n immich-friend \
  --from-literal=role-id="$(tofu output -raw approle_role_id)" \
  --from-literal=secret-id="$(tofu output -raw approle_secret_id)"
```

**5. Deploy ESO via ArgoCD**:

```bash
kubectl apply -f k8s/argocd/external-secrets-app.yaml
```

**6. Deploy immich-friend**:

```bash
kubectl apply -f k8s/argocd/immich-friend-app.yaml
```

ESO creates these Kubernetes Secrets from Vault:

- `postgres-credentials` ← `immich-friend/database`
- `authelia-secrets` ← `immich-friend/{oauth,jwt,session,storage,oidc-hmac}`
- `resend-api-key` ← `resend/api`

Secrets update automatically when Vault changes.

## Monitoring

```bash
# Watch pods
kubectl get pods -n immich-friend -w

# Check logs
kubectl logs -n immich-friend deployment/immich -f

# Port-forward to access directly
kubectl port-forward -n immich-friend svc/immich 2283:2283
```

## Switching Between Podman and K3s

Set in `config.nix`:

```nix
server.containerBackend = "k3s";  # or "podman"
```

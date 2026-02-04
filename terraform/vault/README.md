# Vault Configuration with OpenTofu

Infrastructure-as-code for HashiCorp Vault secrets management using OpenTofu (open-source Terraform alternative).

**Status**: Fully operational IaC implementation managing production Vault configuration. Core secret generation, AppRole authentication, and Kubernetes integration are stable. Ongoing work includes expanding secret coverage, implementing additional auth methods, and enhancing state management practices.

## What This Does

This OpenTofu configuration:
- Enables AppRole authentication in Vault
- Creates KV v2 secrets engines (`immich-friend/`, `resend/`)
- Generates random secrets (database passwords, OAuth secrets, JWT tokens)
- Stores domain configuration in Vault (synced to k8s via ESO)
- Creates AppRole policy and role for k8s authentication
- Creates bootstrap k8s secret (vault-approle) for ESO
- Manages k8s Ingress resource with Terraform-controlled domains

## Why OpenTofu?

OpenTofu is the open-source fork of Terraform (Linux Foundation):
- Same HCL syntax as Terraform
- Drop-in replacement (same providers, same workflow)
- Open-source (MPL 2.0 license)

## Prerequisites

**1. Install OpenTofu**:
```bash
# On NixOS, add to your configuration.nix or home.nix:
environment.systemPackages = with pkgs; [
  opentofu
];

# Or use nix-shell:
nix-shell -p opentofu
```

**2. Set up kubectl access**:
You need kubectl configured to access the k3s cluster. See [k8s/README.md](../../k8s/README.md) for setup instructions.

```bash
# Test kubectl access
kubectl get nodes

# If this fails, follow the kubectl setup guide first
```

**3. Vault must be initialized and unsealed**:
```bash
# Check Vault status
kubectl exec -it vault-0 -n vault -- vault status
# Should show "Sealed: false"
```

**4. Vault access**:
Vault must be accessible from your deploy PC. Options:

```bash
# Option 1: SSH tunnel (recommended)
ssh -L 8300:localhost:8300 your-server

# Option 2: Direct access via LAN (if ports are open)
# Already configured in providers.tf to use server IP

# Option 3: VPN access
# Connect via WireGuard and use server's VPN IP
```

## Initial Setup

**1. Configure your domains**:

Edit `terraform.tfvars` and set your domains:

```bash
cd terraform/vault
cp terraform.tfvars.example terraform.tfvars  # If not already exists
nano terraform.tfvars
```

Set these values:
```hcl
vault_address   = "http://192.168.4.105:8300"  # Your server IP
base_domain     = "example.com"
immich_domain   = "immich.example.com"
authelia_domain = "auth.example.com"
admin_email     = "admin@example.com"

# Generate OAuth hash with:
# kubectl run -it --rm hash --image=authelia/authelia:latest --restart=Never -- \
#   authelia crypto hash generate pbkdf2 --variant sha512 --random.length 32 --password 'your-secret'
oauth_client_secret_hashed = "$pbkdf2-sha512$310000$..."

# Optional: Set later or via variable
# resend_api_key = "re_..."
```

**2. Set environment variable for root token**:
```bash
export VAULT_TOKEN="<your-root-token>"
```

**3. Initialize OpenTofu**:
```bash
tofu init
```

**4. Review the plan**:
```bash
tofu plan
```

This shows what will be created (AppRole, secrets, policies, k8s resources).

**5. Apply the configuration**:
```bash
tofu apply
```

Type `yes` to confirm.

## Importing Existing Resources

If resources already exist in Vault or Kubernetes (from previous manual setup), import them:

```bash
# Import namespace
tofu import kubernetes_namespace.immich_friend immich-friend

# Import secret (format: namespace/secret-name)
tofu import kubernetes_secret.vault_approle immich-friend/vault-approle

# Import ingress (format: namespace/ingress-name)
tofu import kubernetes_ingress_v1.immich_friend immich-friend/immich-friend-ingress

# Then run tofu apply to sync state
tofu apply
```

**5. Get the AppRole credentials**:
```bash
# View all outputs
tofu output

# Get just the role-id
tofu output -raw approle_role_id

# Get the secret-id (sensitive)
tofu output -raw approle_secret_id

# Get the kubectl command
tofu output -raw kubernetes_secret_command
```

**6. Create the Kubernetes secret**:
```bash
# Copy the command from output and run it:
kubectl create secret generic vault-approle -n immich-friend \
  --from-literal=role-id="<role-id>" \
  --from-literal=secret-id="<secret-id>"
```

## Setting the Resend API Key

**Option 1: Set via variable (recommended)**:
```bash
tofu apply -var="resend_api_key=re_xxxxxxxxxxxx"
```

**Option 2: Set manually after apply**:
```bash
kubectl exec -it vault-0 -n vault -- \
  env VAULT_TOKEN="$VAULT_TOKEN" \
  vault kv put resend/api key="re_xxxxxxxxxxxx"
```

## State Management

**State file location**: `terraform.tfstate` (local)

This file contains sensitive data (secrets, tokens). It is gitignored.

**For production**, use remote state:
- S3 + DynamoDB (AWS)
- GCS (Google Cloud)
- Azure Blob Storage
- Terraform Cloud / Spacelift

**For homelab**: Local state is acceptable.

## Workflow: Making Changes

### Updating Domains

1. Edit `terraform.tfvars` with new domains
2. Run `tofu apply`
3. Terraform will:
   - Update Vault secrets (ESO syncs to k8s)
   - Update Ingress resource
4. Pods will automatically reload (if using Reloader)

### Rotating Secrets

```bash
# Destroy and recreate specific secret
tofu destroy -target=vault_kv_secret_v2.database
tofu apply

# Or taint and apply
tofu taint random_password.oauth_secret
tofu apply
```

**Note**: After rotation, ExternalSecrets will sync within 5 minutes (refresh interval). To force immediate sync:

```bash
kubectl delete externalsecret authelia-secrets -n immich-friend
```

## Common Commands

### Viewing State

```bash
# List all managed resources
tofu state list

# Show details of a specific resource
tofu state show vault_kv_secret_v2.oauth
tofu state show kubernetes_ingress_v1.immich_friend

# View all outputs
tofu output

# View specific output
tofu output -raw approle_role_id
```

### Updating Configuration

```bash
# After editing terraform.tfvars or .tf files
tofu plan    # Preview changes
tofu apply   # Apply changes

# Apply with variable override
tofu apply -var="resend_api_key=re_new_key"

# Auto-approve (skip confirmation)
tofu apply -auto-approve
```

### Managing Secrets

```bash
# Rotate a specific secret (generates new random value)
tofu taint random_password.oauth_secret
tofu apply

# Or destroy and recreate
tofu destroy -target=vault_kv_secret_v2.oauth
tofu apply

# Force ExternalSecret refresh in k8s after rotation
kubectl delete externalsecret authelia-secrets -n immich-friend
```

### Troubleshooting

```bash
# Refresh state from actual infrastructure
tofu refresh

# Fix state drift
tofu apply

# Validate configuration syntax
tofu validate

# Format code
tofu fmt

# Show dependency graph
tofu graph | dot -Tpng > graph.png
```

### Cleaning Up

```bash
# Destroy specific resource
tofu destroy -target=kubernetes_ingress_v1.immich_friend

# Destroy everything (DANGEROUS)
tofu destroy
```

## Files

- `providers.tf` - Provider configuration (Vault, Kubernetes, Random)
- `main.tf` - AppRole authentication, k8s namespace, secret, and ingress
- `secrets.tf` - Secret generation and Vault storage
- `variables.tf` - Input variables (domains, API keys)
- `outputs.tf` - AppRole credentials and setup info
- `terraform.tfvars` - Your configuration (gitignored, contains sensitive data)
- `.gitignore` - Excludes state files and secrets

## Integration with ESO

After running `tofu apply`:

1. OpenTofu configures Vault
2. Create Kubernetes secret with AppRole credentials
3. Deploy ESO via ArgoCD
4. ESO reads from Vault using AppRole
5. ESO creates Kubernetes Secrets automatically

See `k8s/immich-friend/README.md` for ESO deployment.

## Troubleshooting

**"Error: missing vault address"**:
- Set `VAULT_ADDR` environment variable
- Ensure port-forward is running

**"Error: permission denied"**:
- Check `VAULT_TOKEN` is set correctly
- Use root token for initial setup

**"Error: already exists"**:
- Resource already created (normal if re-running)
- Import existing resource or destroy and recreate

**State drift**:
```bash
# Refresh state to match reality
tofu refresh

# Re-apply to fix drift
tofu apply
```

## Production Considerations

**Current setup** is suitable for homelab and development environments.

**For production**, add:
- **Remote state** - S3/GCS backend with state locking
- **Workspace isolation** - Separate dev/staging/prod
- **CI/CD integration** - Automated tofu plan/apply
- **State encryption** - Encrypted backend storage
- **Access control** - RBAC for state access
- **Audit logging** - Track all changes

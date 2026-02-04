# ArgoCD Applications

This directory uses **ApplicationSet** for fully automated GitOps deployments.

## How It Works

**ApplicationSet automatically discovers and deploys ALL directories in `k8s/`:**

```
k8s/
├── argocd/              (excluded - contains ArgoCD meta-config)
├── vault/               → Auto-creates "vault" Application
├── immich-friend/       → Auto-creates "immich-friend" Application
├── ingress-nginx/       → Auto-creates "ingress-nginx" Application
├── reloader/            → Auto-creates "reloader" Application
├── external-secrets/    → Auto-creates "external-secrets" Application
└── any-new-service/     → Auto-creates Application automatically!
```

## Initial Bootstrap (ONE TIME ONLY)

**Prerequisites**: Update Git repository URLs:

1. **config.nix**: Set `container-backend.k3s.gitops.github.repoURL` (see main [README.md](../../README.md#3-k3s-configuration-if-using-k3s))
2. **k8s/argocd/applicationset.yaml**: Update both `repoURL` fields to your fork

Then apply:

```bash
kubectl apply -f k8s/argocd/applicationset.yaml
```

ApplicationSet scans `k8s/*/` and creates Applications for every directory.

## Adding New Services

No manual Application creation needed.

```bash
# 1. Create service directory and manifests
mkdir k8s/monitoring
vim k8s/monitoring/prometheus.yaml

# 2. Commit and push
git add k8s/monitoring
git commit -m "Add monitoring"
git push

# 3. ApplicationSet automatically:
#    - Detects new k8s/monitoring/ directory
#    - Creates "monitoring" Application
#    - Deploys all YAMLs in k8s/monitoring/
```

## Verify Deployment

```bash
# Check Applications
kubectl get applications -n argocd

# Watch sync status
kubectl get applications -n argocd -o wide
```

## GitOps Workflow

After bootstrap, all changes follow this pattern:

1. **Update manifests** in `k8s/{vault,ingress-nginx,immich-friend}/`
2. **Commit and push** to Git
3. **ArgoCD auto-syncs** within seconds (automated sync policy enabled)
4. **Changes deployed** automatically

No manual `kubectl apply` needed after initial bootstrap.

## Application Structure

Each Application manifest defines:

- **source**: Git repository and path
- **destination**: Target Kubernetes cluster and namespace
- **syncPolicy**:
  - `automated.prune`: Delete resources removed from Git
  - `automated.selfHeal`: Revert manual changes
  - `CreateNamespace`: Auto-create target namespace
  - Retry policy with exponential backoff

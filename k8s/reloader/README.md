# Reloader - Automatic Pod Restart on Config Changes

[Reloader](https://github.com/stakater/Reloader) is a Kubernetes operator that watches ConfigMaps and Secrets, automatically triggering rolling updates on Deployments, StatefulSets, and DaemonSets when their configurations change.

## Why Reloader?

**Problem:** Kubernetes doesn't automatically restart pods when ConfigMaps or Secrets change. Pods keep running with stale configuration.

**Solution:** Reloader watches for changes and triggers rolling updates automatically.

## How It Works

1. **Watch**: Reloader monitors all ConfigMaps and Secrets cluster-wide
2. **Detect**: When a ConfigMap/Secret changes, Reloader finds pods using it
3. **Restart**: Triggers a rolling update by updating pod annotations
4. Works with ArgoCD auto-sync

## Usage

Add annotation to your Deployment/StatefulSet/DaemonSet:

```yaml
metadata:
  annotations:
    reloader.stakater.com/auto: "true"
```

Reloader will automatically restart the pods whenever their ConfigMaps or Secrets change.

### Advanced Usage

**Watch specific ConfigMap:**

```yaml
metadata:
  annotations:
    configmap.reloader.stakater.com/reload: "my-config"
```

**Watch specific Secret:**

```yaml
metadata:
  annotations:
    secret.reloader.stakater.com/reload: "my-secret"
```

**Watch multiple:**

```yaml
metadata:
  annotations:
    configmap.reloader.stakater.com/reload: "config1,config2"
    secret.reloader.stakater.com/reload: "secret1,secret2"
```

## Verification

```bash
# Check Reloader is running
kubectl get pods -n reloader

# Check Reloader logs
kubectl logs -n reloader -l app=reloader -f

# Reloader watches all namespaces automatically
```

## Security

Reloader uses:

- **ServiceAccount** with minimal RBAC permissions
- **ClusterRole** (read ConfigMaps/Secrets, update Deployments/StatefulSets)
- **Non-root** container (UID 65534)
- **Read-only filesystem**
- **No privilege escalation**

## Example

When you update a ConfigMap:

```bash
kubectl edit configmap vault-config -n vault
```

Reloader automatically:

1. Detects the change
2. Finds the Vault StatefulSet (has `reloader.stakater.com/auto: "true"`)
3. Updates StatefulSet annotation to trigger rolling update
4. Vault pod restarts with new configuration

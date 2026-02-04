# Vault Configuration for immich-friend Secrets Management
# This configuration sets up AppRole authentication and KV v2 secrets engines

# Enable AppRole authentication
resource "vault_auth_backend" "approle" {
  type = "approle"
}

# Enable KV v2 secrets engine for immich-friend
resource "vault_mount" "immich_friend" {
  path        = "immich-friend"
  type        = "kv"
  options     = { version = "2" }
  description = "KV v2 secrets for immich-friend services"
}

# Enable KV v2 secrets engine for resend
resource "vault_mount" "resend" {
  path        = "resend"
  type        = "kv"
  options     = { version = "2" }
  description = "KV v2 secrets for Resend email service"
}

# Create policy for immich-friend AppRole
resource "vault_policy" "immich_friend" {
  name = "immich-friend"

  policy = <<EOT
# Read secrets for immich-friend services
path "immich-friend/data/*" {
  capabilities = ["read"]
}

path "resend/data/api" {
  capabilities = ["read"]
}
EOT
}

# Create AppRole role for immich-friend
resource "vault_approle_auth_backend_role" "immich_friend" {
  backend        = vault_auth_backend.approle.path
  role_name      = "immich-friend"
  token_policies = [vault_policy.immich_friend.name]
  token_ttl      = 3600  # 1 hour
  token_max_ttl  = 14400 # 4 hours
}

# Get the role ID (static, safe to output)
data "vault_approle_auth_backend_role_id" "immich_friend" {
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.immich_friend.role_name
}

# Generate a secret ID (sensitive, changes on each apply)
resource "vault_approle_auth_backend_role_secret_id" "immich_friend" {
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.immich_friend.role_name
}

# Create Kubernetes secret for ESO to authenticate with Vault
# This is a bootstrap secret - ESO needs it to fetch other secrets from Vault
resource "kubernetes_namespace" "immich_friend" {
  metadata {
    name = "immich-friend"
  }
}

resource "kubernetes_secret" "vault_approle" {
  metadata {
    name      = "vault-approle"
    namespace = kubernetes_namespace.immich_friend.metadata[0].name
  }

  data = {
    role-id   = data.vault_approle_auth_backend_role_id.immich_friend.role_id
    secret-id = vault_approle_auth_backend_role_secret_id.immich_friend.secret_id
  }

  type = "Opaque"
}

# Create Ingress resource with domains from variables
# Single source for domains - set once in terraform.tfvars
resource "kubernetes_ingress_v1" "immich_friend" {
  metadata {
    name      = "immich-friend-ingress"
    namespace = kubernetes_namespace.immich_friend.metadata[0].name
    annotations = {
      "nginx.ingress.kubernetes.io/proxy-body-size"            = "0"
      "nginx.ingress.kubernetes.io/proxy-buffering"            = "off"
      "nginx.ingress.kubernetes.io/proxy-request-buffering"    = "off"
      "nginx.ingress.kubernetes.io/backend-protocol"           = "HTTP"
      "nginx.ingress.kubernetes.io/configuration-snippet"      = <<-EOT
        # Forward headers for Authelia
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-URI $request_uri;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Original-URL https://$http_host$request_uri;

        # Bot protection - block common exploit paths
        # Uses $is_blocked_bot_path map defined in ingress-nginx ConfigMap
        if ($is_blocked_bot_path = 1) {
          return 403;
        }
      EOT
    }
  }

  spec {
    ingress_class_name = "nginx"

    # Immich
    rule {
      host = var.immich_domain
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "immich"
              port {
                number = 2283
              }
            }
          }
        }
      }
    }

    # Authelia
    rule {
      host = var.authelia_domain
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "authelia"
              port {
                number = 9091
              }
            }
          }
        }
      }
    }
  }
}

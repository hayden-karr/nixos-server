# Secrets Generation and Storage
# Generates cryptographically secure random secrets and stores them in Vault
# Using ephemeral resources to ensure secrets are never stored in Terraform state

# PostgreSQL database password
ephemeral "random_password" "db_password" {
  length  = 32
  special = true
}

resource "vault_kv_secret_v2" "database" {
  mount = vault_mount.immich_friend.path
  name  = "database"

  data_json = jsonencode({
    password = random_password.db_password.result
  })
}

# OAuth client secret
ephemeral "random_password" "oauth_secret" {
  length  = 32
  special = true
}

resource "vault_kv_secret_v2" "oauth" {
  mount = vault_mount.immich_friend.path
  name  = "oauth"

  data_json = jsonencode({
    client_secret        = random_password.oauth_secret.result
    client_secret_hashed = var.oauth_client_secret_hashed
  })
}

# JWT signing secret
ephemeral "random_password" "jwt_secret" {
  length  = 64
  special = true
}

resource "vault_kv_secret_v2" "jwt" {
  mount = vault_mount.immich_friend.path
  name  = "jwt"

  data_json = jsonencode({
    secret = random_password.jwt_secret.result
  })
}

# Session encryption secret
ephemeral "random_password" "session_secret" {
  length  = 32
  special = true
}

resource "vault_kv_secret_v2" "session" {
  mount = vault_mount.immich_friend.path
  name  = "session"

  data_json = jsonencode({
    secret = random_password.session_secret.result
  })
}

# Storage encryption key
ephemeral "random_password" "storage_key" {
  length  = 32
  special = true
}

resource "vault_kv_secret_v2" "storage" {
  mount = vault_mount.immich_friend.path
  name  = "storage"

  data_json = jsonencode({
    key = random_password.storage_key.result
  })
}

# OIDC HMAC secret
ephemeral "random_password" "oidc_hmac_secret" {
  length  = 32
  special = true
}

resource "vault_kv_secret_v2" "oidc_hmac" {
  mount = vault_mount.immich_friend.path
  name  = "oidc-hmac"

  data_json = jsonencode({
    secret = random_password.oidc_hmac_secret.result
  })
}

# Domain configuration
resource "vault_kv_secret_v2" "domains" {
  mount = vault_mount.immich_friend.path
  name  = "domains"

  data_json = jsonencode({
    base        = var.base_domain
    immich      = var.immich_domain
    authelia    = var.authelia_domain
    admin_email = var.admin_email
  })
}

# Resend API key (must be set manually via variable or after initial apply)
# This is a placeholder - update with your actual API key
resource "vault_kv_secret_v2" "resend_api" {
  mount = vault_mount.resend.path
  name  = "api"

  data_json = jsonencode({
    key = var.resend_api_key
  })

  # Only create if API key is provided
  count = var.resend_api_key != "" ? 1 : 0
}

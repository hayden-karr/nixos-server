# Outputs for ESO Integration
# These values are used to create the Kubernetes vault-approle secret

output "approle_role_id" {
  description = "AppRole Role ID for immich-friend (safe to output)"
  value       = data.vault_approle_auth_backend_role_id.immich_friend.role_id
}

output "approle_secret_id" {
  description = "AppRole Secret ID for immich-friend (sensitive - handle securely)"
  value       = vault_approle_auth_backend_role_secret_id.immich_friend.secret_id
  sensitive   = true
}

output "kubernetes_secret_command" {
  description = "Command to create the Kubernetes secret for ESO"
  value       = <<-EOT
    kubectl create secret generic vault-approle -n immich-friend \
      --from-literal=role-id="${data.vault_approle_auth_backend_role_id.immich_friend.role_id}" \
      --from-literal=secret-id="${vault_approle_auth_backend_role_secret_id.immich_friend.secret_id}"
  EOT
  sensitive   = true
}

output "summary" {
  description = "Configuration summary"
  value = {
    vault_address          = "http://vault.vault.svc.cluster.local:8200"
    approle_path          = vault_auth_backend.approle.path
    approle_role_name     = vault_approle_auth_backend_role.immich_friend.role_name
    policy_name           = vault_policy.immich_friend.name
    immich_secrets_path   = vault_mount.immich_friend.path
    resend_secrets_path   = vault_mount.resend.path
  }
}

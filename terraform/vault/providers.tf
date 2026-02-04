terraform {
  required_version = ">= 1.0"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.6"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }

  # State file security:
  # - Ephemeral resources (random_password) are not persisted to state
  # - For production: consider remote state backend (S3, GCS, Terraform Cloud)
  # - Sensitive values are stored in Vault, not in Terraform state
}

provider "vault" {
  # Vault exposed via NodePort on port 30820
  # Access via server IP or SSH tunnel to localhost
  # Default assumes SSH tunnel: ssh -L 30820:localhost:30820 <server-ip>
  address = var.vault_address

  # Token must be provided via environment variable for security:
  # export VAULT_TOKEN="<root-token>"

  # Do not hardcode tokens in configuration files
}

provider "kubernetes" {
  # Uses default kubeconfig location
  # Make sure the server address in the config points to the server IP
  config_path = "~/.kube/config"
}

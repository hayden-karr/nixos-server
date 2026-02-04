# Input Variables for Vault Configuration

variable "vault_address" {
  description = "Vault address (LoadBalancer binds to host, port 8300 to avoid Podman Vault collision)"
  type        = string
  default     = "http://localhost:8300"
}

variable "resend_api_key" {
  description = "Resend email service API key (optional - can be set later)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "base_domain" {
  description = "Base domain for cookies and TOTP issuer (e.g., example.com)"
  type        = string
}

variable "immich_domain" {
  description = "Domain for Immich application (e.g., immich.example.com)"
  type        = string
}

variable "authelia_domain" {
  description = "Domain for Authelia OAuth provider (e.g., auth.example.com)"
  type        = string
}

variable "oauth_client_secret_hashed" {
  description = "Hashed OAuth client secret for Authelia (generate with: echo -n 'your-secret' | authelia crypto hash generate pbkdf2 --variant sha512 --random.length 32)"
  type        = string
  sensitive   = true
}

variable "admin_email" {
  description = "Admin email address for Authelia notifications and user account"
  type        = string
}

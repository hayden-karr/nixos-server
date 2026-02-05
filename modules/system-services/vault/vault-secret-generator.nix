{ pkgs, config, ... }:

# Vault Secret Generator (user-initiated)
# Generates random secrets for containers: tokens (openssl), htpasswd (bcrypt)
# USAGE: vault-generate-secrets [container-name]

let meta = import ./vault-metadata.nix config.serverConfig;

in {
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "vault-generate-secrets" ''
      set -euo pipefail

      RED='\033[0;31m'
      GREEN='\033[0;32m'
      YELLOW='\033[1;33m'
      BLUE='\033[0;34m'
      CYAN='\033[0;36m'
      NC='\033[0m'

      export VAULT_ADDR="${meta.vaultAddr}"

      vault_cmd() {
        local TOKEN
        if command -v doas &> /dev/null; then
          TOKEN=$(doas cat /run/secrets/vault-root-token 2>/dev/null)
        elif command -v sudo &> /dev/null; then
          TOKEN=$(sudo cat /run/secrets/vault-root-token 2>/dev/null)
        else
          echo -e "''${RED}ERROR: Neither doas nor sudo available''${NC}"
          exit 1
        fi

        if [ -z "$TOKEN" ]; then
          echo -e "''${RED}ERROR: Cannot read vault root token''${NC}"
          echo "Make sure you have permission to read /run/secrets/vault-root-token"
          exit 1
        fi

        doas podman exec -e VAULT_TOKEN="$TOKEN" -e VAULT_ADDR="${meta.vaultAddr}" vault vault "$@"
      }

      if ! podman ps --format '{{.Names}}' | grep -q '^vault$'; then
        echo -e "''${RED}ERROR: Vault container is not running''${NC}"
        echo "Start it with: systemctl start podman-vault.service"
        exit 1
      fi

      if ! vault_cmd status 2>&1 | grep -q "Sealed.*false"; then
        echo -e "''${RED}ERROR: Vault is sealed''${NC}"
        echo "Unseal it with: systemctl restart vault-unseal.service"
        exit 1
      fi

      echo -e "''${BLUE}════════════════════════════════════════════════════''${NC}"
      echo -e "''${BLUE}  Vault Secret Generator (User-Initiated)''${NC}"
      echo -e "''${BLUE}════════════════════════════════════════════════════''${NC}"
      echo ""

      secret_exists() {
        local path=$1
        vault_cmd kv get -mount=secret "$path" >/dev/null 2>&1
      }

      gen_random_base64() {
        ${pkgs.openssl}/bin/openssl rand -base64 32
      }

      gen_random_hex() {
        ${pkgs.openssl}/bin/openssl rand -hex 32
      }

      gen_htpasswd() {
        local username=$1
        local password=$2
        echo "$password" | ${pkgs.apacheHttpd}/bin/htpasswd -niB "$username" | sed 's/\$/\\$/g'
      }

      store_secret() {
        local path=$1
        local field=$2
        local value=$3
        local display_name=$4

        if secret_exists "$path"; then
          echo -e "''${YELLOW}⚠ Secret exists: secret/$path''${NC}"
          read -p "  Overwrite? [y/N] " -n 1 -r
          echo
          if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "  ''${CYAN}Skipped: $display_name''${NC}"
            return 0
          fi
        fi

        vault_cmd kv put -mount=secret "$path" "$field=$value" >/dev/null 2>&1
        echo -e "''${GREEN}✓ Generated: $display_name''${NC}"
      }

      generate_vaultwarden() {
        echo -e "\n''${BLUE}═══ vaultwarden (Password Manager) ═══''${NC}\n"

        store_secret "vaultwarden/admin-token" "token" "$(gen_random_base64)" "Admin Token"
        echo -e "''${GREEN}✓ Using dynamic database credentials (auto-rotated every 24h)''${NC}"
      }

      generate_n8n() {
        echo -e "\n''${BLUE}═══ n8n (Workflow Automation) ═══''${NC}\n"

        store_secret "n8n/encryption-key" "key" "$(gen_random_base64)" "Encryption Key"
      }

      generate_pihole() {
        echo -e "\n''${BLUE}═══ pihole (DNS Server) ═══''${NC}\n"

        store_secret "pihole/webpassword" "password" "$(gen_random_base64)" "Web Interface Password"
      }

      generate_restic() {
        echo -e "\n''${BLUE}═══ restic (Backup Server) ═══''${NC}\n"

        echo -e "''${CYAN}Restic requires htpasswd (bcrypt) format''${NC}"
        echo -e "''${YELLOW}Enter username for Restic repository access:''${NC}"
        read -p "Username [admin]: " restic_user
        restic_user=''${restic_user:-admin}

        echo -e "''${YELLOW}Enter password (or leave empty to auto-generate):''${NC}"
        read -s -p "Password: " restic_password
        echo

        if [ -z "$restic_password" ]; then
          restic_password=$(gen_random_base64)
          echo -e "''${GREEN}Auto-generated password: $restic_password''${NC}"
          echo -e "''${YELLOW}⚠ Save this password! It won't be shown again.''${NC}"
        fi

        htpasswd_entry=$(gen_htpasswd "$restic_user" "$restic_password")
        store_secret "restic/htpasswd" "htpasswd" "$htpasswd_entry" "Htpasswd Entry"
      }

      generate_linkwarden() {
        echo -e "\n''${BLUE}═══ linkwarden (Bookmark Manager) ═══''${NC}\n"

        store_secret "linkwarden/nextauth" "secret" "$(gen_random_base64)" "NextAuth Secret"
      }

      generate_samba() {
        echo -e "\n''${BLUE}═══ samba (Network File Sharing) ═══''${NC}\n"

        store_secret "samba/password" "password" "$(gen_random_base64)" "Samba Password"
      }

      show_menu() {
        echo ""
        echo "Available containers:"
        echo "  1) vaultwarden        - Password manager (1 secret)"
        echo "  2) n8n                - Workflow automation (1 secret)"
        echo "  3) pihole             - DNS server (1 secret)"
        echo "  4) restic             - Backup server (htpasswd)"
        echo "  5) linkwarden         - Bookmark manager (1 secret)"
        echo "  6) samba              - Network file sharing (1 secret)"
        echo "  a) All containers     - Generate all secrets"
        echo "  l) List secrets       - Show what's in Vault"
        echo "  q) Quit"
        echo ""
      }

      list_secrets() {
        echo -e "\n''${BLUE}═══ Secrets in Vault ═══''${NC}\n"

        for container in vaultwarden n8n pihole restic linkwarden samba; do
          echo -e "''${CYAN}$container:''${NC}"
          vault_cmd kv list -mount=secret "$container/" 2>/dev/null | tail -n +3 | sed 's/^/  /' || echo -e "  ''${YELLOW}(no secrets)''${NC}"
        done
      }

      if [ $# -eq 0 ]; then
        while true; do
          show_menu
          read -p "Select container: " choice

          case $choice in
            1) generate_vaultwarden ;;
            2) generate_n8n ;;
            3) generate_pihole ;;
            4) generate_restic ;;
            5) generate_linkwarden ;;
            6) generate_samba ;;
            a|A)
              echo -e "\n''${YELLOW}⚠ This will generate secrets for ALL containers''${NC}"
              read -p "Continue? [y/N] " -n 1 -r
              echo
              if [[ $REPLY =~ ^[Yy]$ ]]; then
                generate_vaultwarden
                generate_n8n
                generate_pihole
                generate_restic
                generate_linkwarden
                generate_samba
              fi
              ;;
            l|L) list_secrets ;;
            q|Q)
              echo -e "\n''${BLUE}Goodbye!''${NC}"
              exit 0
              ;;
            *)
              echo -e "''${RED}Invalid choice''${NC}"
              ;;
          esac
        done
      else
        container=$1
        case $container in
          vaultwarden) generate_vaultwarden ;;
          n8n) generate_n8n ;;
          pihole) generate_pihole ;;
          restic) generate_restic ;;
          linkwarden) generate_linkwarden ;;
          samba) generate_samba ;;
          *)
            echo -e "''${RED}ERROR: Unknown container: $container''${NC}"
            echo "Available: vaultwarden, n8n, pihole, restic, linkwarden, samba"
            exit 1
            ;;
        esac
      fi

      echo ""
      echo -e "''${GREEN}════════════════════════════════════════════════════''${NC}"
      echo -e "''${GREEN}  Secret generation complete!''${NC}"
      echo -e "''${GREEN}════════════════════════════════════════════════════''${NC}"
      echo ""
      echo "Next steps:"
      echo "  1. Restart vault agents: systemctl restart 'vault-agent-*.service'"
      echo "  2. Check rendered secrets: ls -la /run/vault/<container>/"
      echo "  3. Restart containers to pick up new secrets"
      echo ""
    '')
  ];
}

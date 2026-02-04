{ config, ... }:

let inherit (config.serverConfig) smtp;
in {
  # SMTP Email Relay - Resend
  # Sends system notifications and alerts via external SMTP service
  # Free tier: 3,000 emails/month, 100/day (perfect for server notifications)
  #
  # Use cases:
  # - System notifications (cron jobs, systemd failures)
  # - Application emails (password resets, notifications)
  # - Monitoring alerts (optional alternative to Discord)

  users.groups.smtp = { };

  # msmtp - Lightweight SMTP client (replaces sendmail)
  programs.msmtp = {
    enable = true;
    setSendmail = true; # Make it the default sendmail command
    defaults = {
      auth = true;
      tls = true;
      tls_trust_file = "/etc/ssl/certs/ca-certificates.crt";
      logfile = "/var/log/msmtp.log";
    };

    accounts = {
      default = {
        inherit (smtp) host port from;
        user = smtp.username;
        passwordeval = "cat /run/vault/resend/resend-api-key";
      };
    };
  };

  # Ensure msmtp can access vault secret (optional - graceful degradation)
  # vault-agent-resend writes to /run/vault/resend/resend-api-key with group smtp
  systemd.services.msmtp-setup = {
    description = "Wait for Resend API key from Vault";
    wantedBy = [ "multi-user.target" ];
    after = [ "vault-agent-resend.service" ];
    wants = [
      "vault-agent-resend.service"
    ]; # wants instead of requires - don't fail if vault not set up

    # Don't run if vault-agent-resend doesn't exist (vault not configured yet)
    unitConfig.ConditionPathExists =
      "/etc/systemd/system/vault-agent-resend.service";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Retry a few times if vault agent is slow to write
      Restart = "on-failure";
      RestartSec = "5s";
      StartLimitBurst = 3;
    };
    script = ''
      # Wait up to 15 seconds for vault secret
      for i in {1..3}; do
        if [ -f /run/vault/resend/resend-api-key ]; then
          echo "✓ Resend API key ready from Vault"
          exit 0
        fi
        echo "Waiting for Vault secret... (attempt $i/3)"
        sleep 5
      done

      # If vault secret doesn't exist, just warn (don't fail - allows system to boot)
      echo "WARNING: Vault secret not found at /run/vault/resend/resend-api-key"
      echo "SMTP email will not work until Vault is configured"
      echo "Run: sudo vault-setup-policies"
      exit 0  # Exit successfully to not block boot
    '';
  };

  # Log file creation managed in modules/storage/file-paths.nix

  # Optional: Enable email aliases for root
  # environment.etc."aliases".text = ''
  #   # Send all root mail to your actual email
  #   root: your-email@example.com
  #   # Forward other system users to root
  #   nobody: root
  #   systemd-timesync: root
  #   systemd-network: root
  # '';

  # SETUP:
  # 1. Create Resend account and verify your domain: https://resend.com/signup (free tier: 3k emails/month)
  # 2. Get API key and add to Vault:
  #    doas podman exec -e VAULT_TOKEN="$(doas cat /run/secrets/vault-root-token)" vault \
  #      vault kv put -mount=secret resend/api key="re_YourApiKeyHere"
  # 3. Update config.nix mail.from with your domain's "from" address
  # 4. Test: echo "Test" | msmtp your-email@example.com
  #
  # NOTE: API key is fetched from Vault at /run/vault/resend/resend-api-key (shared with alertmanager)
}


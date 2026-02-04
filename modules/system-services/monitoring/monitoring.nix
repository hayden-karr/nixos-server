{ config, ... }:

# ================================
# Grafana + Loki + Prometheus + Alertmanager
#
# ARCHITECTURE:
# 1. Promtail → Loki (Log aggregation from fail2ban, systemd, containers, nginx)
# 2. Node Exporter → Prometheus (System metrics: CPU, RAM, disk, network)
# 3. Loki Ruler → Alertmanager (Alert on log patterns like fail2ban bans)
# 4. Prometheus → Alertmanager (Alert on metrics like high CPU, disk full)
# 5. Alertmanager → Discord/SMTP (Send alerts via webhook and/or email)
# 6. Grafana (Visualize everything - metrics + logs in one dashboard)
#
# FEATURES:
# - 7-day log retention (auto-deleted)
# - Configurable alerts (Discord, email, or both - see config.nix)
# - All data stored on SSD for performance
#
# Access: https://monitoring.local (via WireGuard VPN)

let
  inherit (config.serverConfig) user smtp;
  inherit (config.serverConfig.network) localhost;
  inherit (config.serverConfig.monitoring.alerts) discord email;

  # Determine which receiver to use based on config
  receiver = if discord && email then
    "both"
  else if discord then
    "discord"
  else if email then
    "email"
  else
    throw
    "At least one monitoring alert method (discord or email) must be enabled";

in {
  # Add alertmanager user to smtp group to read resend-api-key (if email alerts enabled)
  users = {
    users.alertmanager = {
      isSystemUser = true;
      group = "alertmanager";
      extraGroups = if email then [ "smtp" ] else [ ];
    };
    groups.alertmanager = { };
  };

  # Grafana - Dashboards and visualization
  services = {
    grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "0.0.0.0";
          http_port = 3030;
          domain = "monitoring.local";
          root_url = "https://monitoring.local";
        };
        analytics.reporting_enabled = false;
        # Data stored on SSD
        paths = {
          data = "/mnt/ssd/monitoring/grafana/data";
          logs = "/mnt/ssd/monitoring/grafana/logs";
        };
      };
      provision = {
        enable = true;
        # Auto-configure datasources
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            access = "proxy";
            url = "http://${localhost.ip}:9090";
            isDefault = false;
          }
          {
            name = "Loki";
            type = "loki";
            access = "proxy";
            url = "http://${localhost.ip}:3100";
            isDefault = true;
          }
        ];
      };
    };

    # Loki - Log aggregation
    loki = {
      enable = true;
      configuration = {
        server.http_listen_port = 3100;
        auth_enabled = false;

        ingester = {
          lifecycler = {
            address = localhost.ip;
            ring = {
              kvstore.store = "inmemory";
              replication_factor = 1;
            };
          };
          chunk_idle_period = "5m";
          chunk_retain_period = "30s";
        };

        schema_config.configs = [{
          from = "2025-12-01";
          store = "tsdb";
          object_store = "filesystem";
          schema = "v13";
          index = {
            prefix = "index_";
            period = "24h";
          };
        }];

        storage_config = {
          tsdb_shipper = {
            active_index_directory = "/mnt/ssd/monitoring/loki/tsdb";
            cache_location = "/mnt/ssd/monitoring/loki/cache";
          };
          filesystem.directory = "/mnt/ssd/monitoring/loki/chunks";
        };

        # Retention: Delete logs older than 7 days
        limits_config = {
          retention_period = "168h"; # 7 days
          reject_old_samples = true;
          reject_old_samples_max_age = "168h";
        };

        # Compaction and deletion
        compactor = {
          working_directory = "/mnt/ssd/monitoring/loki/compactor";
          retention_enabled = true;
          retention_delete_delay = "2h";
          retention_delete_worker_count = 150;
          delete_request_store = "filesystem";
        };

        # Ruler - Alert on log patterns
        ruler = {
          enable_api = true;
          enable_alertmanager_v2 = true;
          alertmanager_url = "http://${localhost.ip}:9093";
          storage = {
            type = "local";
            local.directory = "/mnt/ssd/monitoring/loki/rules";
          };
          rule_path = "/mnt/ssd/monitoring/loki/rules-temp";
          ring = { kvstore.store = "inmemory"; };
        };
      };
    };

    # Promtail - Log collector (ships logs to Loki)
    promtail = {
      enable = true;
      configuration = {
        server = {
          http_listen_port = 3031;
          grpc_listen_port = 0;
        };
        clients = [{ url = "http://${localhost.ip}:3100/loki/api/v1/push"; }];

        scrape_configs = [
          # Systemd journal (all system logs)
          {
            job_name = "journal";
            journal = {
              max_age = "12h";
              labels = {
                job = "systemd-journal";
                host = "server";
              };
            };
            relabel_configs = [{
              source_labels = [ "__journal__systemd_unit" ];
              target_label = "unit";
            }];
          }

          # Podman container logs
          {
            job_name = "containers";
            static_configs = [{
              targets = [ "localhost" ];
              labels = {
                job = "containers";
                host = "server";
                __path__ =
                  "/var/lib/containers/storage/overlay-containers/*/userdata/ctr.log";
              };
            }];
            pipeline_stages = [{
              # Parse container name from path
              regex = {
                expression =
                  "/var/lib/containers/storage/overlay-containers/(?P<container_id>[^/]+)/";
              };
            }];
          }

          # Minecraft logs
          {
            job_name = "minecraft";
            static_configs = [{
              targets = [ "localhost" ];
              labels = {
                job = "minecraft";
                app = "minecraft";
                __path__ = "/mnt/ssd/minecraft/logs/latest.log";
              };
            }];
          }

          # Minecraft modded logs
          {
            job_name = "minecraft-modded";
            static_configs = [{
              targets = [ "localhost" ];
              labels = {
                job = "minecraft-modded";
                app = "minecraft";
                __path__ = "/mnt/ssd/minecraft-modded/logs/latest.log";
              };
            }];
          }

          # fail2ban logs (from systemd journal)
          {
            job_name = "fail2ban";
            journal = {
              max_age = "12h";
              labels = {
                job = "fail2ban";
                host = "server";
              };
              matches = "_SYSTEMD_UNIT=fail2ban.service";
            };
            relabel_configs = [{
              source_labels = [ "__journal__systemd_unit" ];
              target_label = "unit";
            }];
          }

          # Nginx access logs (if you add it later)
          {
            job_name = "nginx";
            static_configs = [{
              targets = [ "localhost" ];
              labels = {
                job = "nginx";
                __path__ = "/var/log/nginx/*.log";
              };
            }];
          }
        ];
      };
    };

    # Prometheus - Metrics collection
    prometheus = {
      enable = true;
      port = 9090;

      # 7 day retention (data stored in default /var/lib/prometheus)
      extraFlags = [ "--storage.tsdb.retention.time=7d" ];

      scrapeConfigs = [
        # Prometheus self-monitoring
        {
          job_name = "prometheus";
          static_configs = [{ targets = [ "${localhost.ip}:9090" ]; }];
        }

        # Node exporter (system metrics)
        {
          job_name = "node";
          static_configs = [{ targets = [ "${localhost.ip}:9100" ]; }];
        }

        # Loki metrics
        {
          job_name = "loki";
          static_configs = [{ targets = [ "${localhost.ip}:3100" ]; }];
        }

        # Grafana metrics
        {
          job_name = "grafana";
          static_configs = [{ targets = [ "${localhost.ip}:3030" ]; }];
        }
      ];

      # Alerting rules
      rules = [''
        groups:
          - name: alerts
            interval: 30s
            rules:
              # Alert on high CPU
              - alert: HighCPU
                expr: 100 - (avg by(instance)(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
                for: 5m
                labels:
                  severity: warning
                annotations:
                  summary: "High CPU Usage Detected"
                  description: "Server CPU usage has been above 80% for 5 minutes. Current usage: {{ $value | humanize }}%. Consider checking running processes with 'htop' or 'systemctl --failed'."

              # Alert on disk filling up
              - alert: DiskSpaceLow
                expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 10
                labels:
                  severity: critical
                annotations:
                  summary: "CRITICAL: Low Disk Space"
                  description: "Root filesystem has less than 10% free space remaining. Free up space immediately to prevent system instability. Check disk usage with 'df -h' and 'du -sh /*'."

              # Alert on container restarts
              - alert: ContainerRestart
                expr: increase(node_systemd_unit_state{name=~"podman-.*",state="failed"}[10m]) > 0
                labels:
                  severity: warning
                annotations:
                  summary: "Container Failed"
                  description: "Container {{ $labels.name }} has failed in the last 10 minutes. Check logs with 'journalctl -u {{ $labels.name }} --since \"10 minutes ago\"'."
      ''];

      alertmanagers =
        [{ static_configs = [{ targets = [ "${localhost.ip}:9093" ]; }]; }];

      # Alertmanager - Send alerts to Discord
      alertmanager = {
        enable = true;
        port = 9093;

        configuration = {
          global = { resolve_timeout = "5m"; };

          route = {
            group_by = [ "alertname" ];
            group_wait = "30s"; # Wait 30s to batch alerts
            group_interval = "5m"; # Wait 5min before sending updates
            repeat_interval = "1h"; # Repeat every hour if still firing
            inherit receiver;
          };

          receivers = [
            # Combined receiver - sends to both Discord and email
            {
              name = "both";
              discord_configs = [{
                webhook_url_file = "/run/vault/discord/discord-webhook-url";
                send_resolved = false; # Only send firing alerts, not resolved
                title =
                  "{{ .GroupLabels.alertname }} - {{ .CommonLabels.severity | toUpper }}";
                message = ''
                  {{ range .Alerts -}}
                  **Alert:** {{ .Annotations.summary }}
                  **Details:** {{ .Annotations.description }}
                  {{ if .Labels.banned_ip }}**Banned IP:** {{ .Labels.banned_ip }}{{ end }}
                  **Started:** {{ .StartsAt.Format "2006-01-02 15:04:05 MST" }}
                  {{ end -}}
                '';
              }];
              # Email notifications
              email_configs = [{
                to = user.email;
                inherit (smtp) from;
                smarthost = "${smtp.host}:${toString smtp.port}";
                auth_username = smtp.username;
                auth_password_file = "/run/vault/resend/resend-api-key";
                headers = {
                  Subject =
                    "[{{ .CommonLabels.severity | toUpper }}] {{ .GroupLabels.alertname }} - Server Alert";
                };
                html = ''
                  <h2>{{ .GroupLabels.alertname }}</h2>
                  {{ range .Alerts }}
                  <p><strong>Summary:</strong> {{ .Annotations.summary }}</p>
                  <p><strong>Description:</strong> {{ .Annotations.description }}</p>
                  {{ if .Labels.banned_ip }}<p><strong>Banned IP:</strong> <code>{{ .Labels.banned_ip }}</code></p>{{ end }}
                  <p><strong>Status:</strong> {{ .Status }}</p>
                  <p><strong>Started:</strong> {{ .StartsAt.Format "2006-01-02 15:04:05 MST" }}</p>
                  <hr>
                  {{ end }}
                '';
              }];
            }
            # Discord only
            {
              name = "discord";
              discord_configs = [{
                webhook_url_file = "/run/vault/discord/discord-webhook-url";
                send_resolved = true;
                title = "{{ .GroupLabels.alertname }}";
                message = ''
                  {{ range .Alerts }}{{ .Annotations.summary }}
                  {{ .Annotations.description }}
                  {{ end }}'';
              }];
            }
            # Email only
            {
              name = "email";
              email_configs = [{
                to = user.email;
                inherit (smtp) from;
                smarthost = "${smtp.host}:${toString smtp.port}";
                auth_username = smtp.username;
                auth_password_file = "/run/vault/resend/resend-api-key";
                headers = {
                  Subject = "[Server Alert] {{ .GroupLabels.alertname }}";
                };
              }];
            }
          ];
        };
      };
    };
  };

  # Ensure alertmanager starts after vault agents for shared secrets
  systemd.services.alertmanager = {
    after = (if discord then [ "vault-agent-discord.service" ] else [ ])
      ++ (if email then [ "vault-agent-resend.service" ] else [ ]);
    requires = (if discord then [ "vault-agent-discord.service" ] else [ ])
      ++ (if email then [ "vault-agent-resend.service" ] else [ ]);
  };

  # Create Loki ruler alert rules for fail2ban
  systemd.services.loki-ruler-setup = {
    description = "Setup Loki Ruler alert rules";
    wantedBy = [ "loki.service" ];
    before = [ "loki.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /mnt/ssd/monitoring/loki/rules/fake

      cat > /mnt/ssd/monitoring/loki/rules/fake/alerts.yaml <<'EOF'
      groups:
        - name: fail2ban_alerts
          interval: 1m
          rules:
            - alert: Fail2BanAlert
              expr: |
                count_over_time({job="fail2ban"} |= "Ban" [5m]) > 0
              labels:
                severity: warning
              annotations:
                summary: "Security Alert: IP Banned by fail2ban"
                description: "fail2ban has banned {{ $value }} IP address(es) in the last 5 minutes. Check logs with: journalctl -u fail2ban --since '5 minutes ago' | grep Ban"

            - alert: Fail2banExploitDetected
              expr: |
                count_over_time({job="fail2ban", jail="minecraft-exploit"} |= "Ban" [1m]) > 0
              labels:
                severity: critical
              annotations:
                summary: "CRITICAL: Minecraft Exploit Attempt Blocked"
                description: "fail2ban detected and blocked a Minecraft exploit attempt (Log4Shell/JNDI). The attacker has been banned. Check: journalctl -u fail2ban --since '5 minutes ago' | grep minecraft-exploit"
      EOF

      chmod -R 755 /mnt/ssd/monitoring/loki/rules
    '';
  };

  # Node exporter - System metrics
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    enabledCollectors = [
      "systemd"
      "processes"
      "cpu"
      "meminfo"
      "diskstats"
      "filesystem"
      "netstat"
    ];
  };

  # SETUP:
  # 1. Configure alert methods in config.nix:
  #    monitoring.alerts.discord = true/false
  #    monitoring.alerts.email = true/false
  #
  # 2. Add secrets to Vault (based on enabled methods):
  #    - Discord: Create webhook (Server Settings → Webhooks) and add to Vault
  #    - Email: Get Resend API key and add to Vault
  #    See secrets.yaml.template for Vault setup commands
  #
  # 3. Update config.nix with your email address (if email alerts enabled)
  #
  # 4. Access Grafana: https://monitoring.local (VPN required)
  #    Default login: admin/admin (change on first login)
  #
  # QUERYING LOGS:
  # Explore → Loki datasource, examples:
  # - {job="minecraft"} - All Minecraft logs
  # - {job="fail2ban"} |= "Ban" - fail2ban bans
  # - {job="systemd-journal",unit="sshd"} - SSH attempts
  # - {job="containers"} - All container logs
  #
  # ALERTS (automatic via configured methods):
  # Loki (log-based): fail2ban bans, Minecraft exploits
  # Prometheus (metric-based): High CPU, low disk, container failures
  #
  # Test: doas systemctl restart prometheus
}

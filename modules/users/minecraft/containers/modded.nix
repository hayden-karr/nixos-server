_:

# Minecraft Modded Server - Fabric (Rootless container)
# Runs on port 25566
# Secrets managed by system-level Vault Agent (see modules/vault/vault-agents.nix)

{
  services.podman = {
    networks.minecraft-modded = {
      driver = "bridge";
      subnet = "10.90.7.0/24";
    };

    containers.minecraft-modded = {
      image = "itzg/minecraft-server:latest";
      autoStart = false;
      network = "minecraft-modded";
      ports = [ "25566:25565" ];

      volumes = [
        "/mnt/ssd/minecraft-modded:/data:U"
        "/run/vault/minecraft-modded/whitelist.json:/run/secrets/whitelist:ro"
      ];

      environment = {
        EULA = "TRUE";

        # Mod loader - FABRIC
        TYPE = "FABRIC";
        VERSION = "1.21.8";

        # Memory
        MEMORY = "6G";

        # Performance
        JVM_XX_OPTS = "-XX:+UseZGC -XX:+ZGenerational";
        VIEW_DISTANCE = "8";
        SIMULATION_DISTANCE = "6";

        # Server settings
        MOTD = "Modded Server!";
        ENABLE_RCON = "false";

        # Whitelist from Vault
        ENABLE_WHITELIST = "true";
        ENFORCE_WHITELIST = "true";
        WHITELIST_FILE = "/run/secrets/whitelist";
      };

      extraPodmanArgs = [
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
        "--read-only"
        "--tmpfs=/tmp:rw,noexec,nosuid"
      ];

      extraConfig.Unit = {
        # System-level vault-agent-minecraft-modded.service must be running
        After = [ "vault-agent-minecraft-modded.service" ];
        Wants = [ "vault-agent-minecraft-modded.service" ];
      };
    };
  };
}

_:

# Minecraft Server - Vanilla (Paper)
# Runs as rootless container under minecraft user on port 25565

{
  services.podman = {
    networks.minecraft = {
      driver = "bridge";
      subnet = "10.90.6.0/24";
    };

    containers.minecraft = {
      image = "itzg/minecraft-server:latest";
      autoStart = false;
      network = "minecraft";
      ports = [ "25565:25565" ];

      volumes = [ "/mnt/ssd/minecraft:/data" ];

      environment = {
        EULA = "TRUE";
        TYPE = "PAPER";
        MEMORY = "4G";
        ENABLE_RCON = "false";
        MOTD = "Hello!";

        # Enable console pipe for mc-send-to-console command
        CREATE_CONSOLE_IN_PIPE = "true";

        # Whitelist - manage directly on server in /mnt/ssd/minecraft/whitelist.json
        # Or use WHITELIST env var with comma-separated usernames
        ENABLE_WHITELIST = "true";
        ENFORCE_WHITELIST = "true";

        # Performance optimizations
        JVM_XX_OPTS = "-XX:+UseZGC -XX:+ZGenerational";
        VIEW_DISTANCE = "8";
        SIMULATION_DISTANCE = "6";
        MAX_TICK_TIME = "60000";
        SPAWN_PROTECTION = "0";
      };

      extraPodmanArgs = [
        "--security-opt=no-new-privileges"
        # Note: --cap-drop=ALL and --read-only are too restrictive for Minecraft
        # The container needs to write to /etc/nsswitch.conf and switch users
        "--tmpfs=/tmp:rw,exec,nosuid" # NEEDS exec for JVM!
        "--tmpfs=/run:rw,noexec,nosuid"
      ];
    };
  };
}

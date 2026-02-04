{ pkgs, ... }:

# Podman Network Configuration for immich-friend
# Isolated bridge network for all immich-friend containers
# Provides internal DNS for container-to-container communication
#
# FIX: Podman's aardvark-dns (10.90.8.1) isn't ready when containers start at boot
# Solution: Manually create network with explicit DNS servers using podman network create
# Can't use services.podman.networks - it doesn't support --dns flags

{
  # Create network manually with DNS servers
  systemd.user.services.podman-network-immich-friend = {
    Unit = {
      Description = "Podman network for immich-friend with DNS servers";
      Before = [
        "podman-authelia-friend.service"
        "podman-immich-friend-postgres.service"
        "podman-immich-friend-redis.service"
        "podman-immich-friend.service"
      ];
    };

    Service = {
      Type = "oneshot";
      RemainAfterExit = true;

      # Create network with explicit DNS servers
      ExecStart = "${pkgs.writeShellScript "create-immich-network" ''
        # Remove if exists (may be in bad state)
        ${pkgs.podman}/bin/podman network rm immich-friend 2>/dev/null || true

        # Create with DNS servers so containers can resolve external domains
        ${pkgs.podman}/bin/podman network create immich-friend \
          --subnet 10.90.8.0/24 \
          --dns 1.1.1.1 \
          --dns 1.0.0.1
      ''}";

      ExecStop = "${pkgs.podman}/bin/podman network rm immich-friend 2>/dev/null || true";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}

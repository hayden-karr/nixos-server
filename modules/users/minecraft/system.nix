_: {
  # System user for minecraft - rootless container isolation
  users = {
    users.minecraft = {
      isSystemUser = true; # System user - no login, no password
      group = "minecraft";
      extraGroups = [ "podman" ];
      uid = 1002;
      home = "/var/lib/minecraft";
      createHome = true; # Required for home-manager
      linger = true; # Allow user services to run without login
      # Required for rootless containers - maps container UIDs to unprivileged host UIDs
      # Container UID 0 (root) maps to host UID 300000+, preventing privilege escalation
      subUidRanges = [{
        startUid = 300000;
        count = 65536;
      }];
      subGidRanges = [{
        startGid = 300000;
        count = 65536;
      }];
    };

    groups.minecraft.gid = 1002;
  };
}

_: {
  # System user for immich-friend - rootless container isolation
  users = {
    users.immich-friend = {
      isSystemUser = true; # System user - no login, no password
      group = "immich-friend";
      extraGroups = [ "podman" "vault-access" "smtp" ];
      uid = 1001;
      home = "/var/lib/immich-friend";
      createHome = true; # Required for home-manager
      linger = true; # Allow user services to run without login
      # Required for rootless containers - maps container UIDs to unprivileged host UIDs
      # Container UID 0 (root) maps to host UID 200000+, preventing privilege escalation
      subUidRanges = [{
        startUid = 200000;
        count = 65536;
      }];
      subGidRanges = [{
        startGid = 200000;
        count = 65536;
      }];
    };

    groups.immich-friend.gid = 1001;
  };
}

_: {
  # Boot settings
  boot = {
    loader = {

      limine = {
        enable = true;
        maxGenerations = 10;
      };
    };

    tmp = {
      useTmpfs = true;
      tmpfsSize = "4G";
    };

    supportedFilesystems = [ "ntfs" "fuse" "exfat" ];

    kernelParams = [ "quiet" "loglevel=3" ];

    # Kernel hardening and performance settings
    kernel.sysctl = {
      # Kernel security hardening (restrict unprivileged access to kernel features)
      "kernel.unprivileged_bpf_disabled" =
        1; # Prevent unprivileged BPF (prevent exploits)
      "kernel.kptr_restrict" = 2; # Hide kernel pointers from unprivileged users
      "kernel.dmesg_restrict" = 1; # Restrict kernel log access

      # Filesystem performance tuning (optimized for server workloads)
      "vm.dirty_ratio" = 10; # Start writing dirty pages at 10% RAM
      "vm.dirty_background_ratio" = 5; # Background writes at 5% RAM
    };

  };
}


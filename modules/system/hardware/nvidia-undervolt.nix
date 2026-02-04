{ config, lib, pkgs, ... }:

# ═══════════════════════════════════════════════════════════════════════════
# NVIDIA GPU Undervolting Module
# ═══════════════════════════════════════════════════════════════════════════
# Reduces GPU power consumption and heat by limiting clock speeds and power
#
# WHAT IS UNDERVOLTING?
# - Reduces power consumption without significantly impacting performance
# - Lowers GPU temperatures (quieter fans, longer lifespan)
# - Useful for servers running 24/7 with GPU workloads (ML, transcoding)
#
# HOW IT WORKS:
# - Sets GPU clock speed range (min/max MHz)
# - Limits maximum power draw (watts)
# - Adjusts clock offset for fine-tuning
#
# SAFETY:
# - GPU won't be damaged - worst case is instability/crashes if too aggressive
# - Settings reset on reboot (not permanent to BIOS)
# - Can be disabled by setting enable = false
# ═══════════════════════════════════════════════════════════════════════════

with lib;

let
  cfg = config.services.nvidia-undervolt;

  # Python environment with pynvml library for NVIDIA GPU control
  pythonWithPynvml = pkgs.python3.withPackages (ps: with ps; [ pynvml ]);

  # Python script that applies undervolt settings using NVIDIA Management Library
  undervoltScript = pkgs.writeScriptBin "undervolt-nvidia-device" ''
    #!${pythonWithPynvml}/bin/python3

    from pynvml import *
    from ctypes import byref
    import sys

    try:
        # Initialize NVIDIA Management Library
        print("Initializing NVML...")
        nvmlInit()

        # Get handle to GPU device (gpuIndex = 0 for first GPU)
        print("Getting GPU device ${toString cfg.gpuIndex}...")
        device = nvmlDeviceGetHandleByIndex(${toString cfg.gpuIndex})

        # Lock GPU clocks to a specific range (prevents boost, reduces power)
        print("Setting GPU locked clocks: ${toString cfg.minClock}-${
          toString cfg.maxClock
        } MHz...")
        nvmlDeviceSetGpuLockedClocks(device, ${toString cfg.minClock}, ${
          toString cfg.maxClock
        })

        # Set maximum power draw limit (in milliwatts)
        print("Setting power management limit: ${
          toString cfg.powerLimit
        } mW...")
        nvmlDeviceSetPowerManagementLimit(device, ${toString cfg.powerLimit})

        # Apply clock offset (fine-tune performance within locked range)
        print("Setting clock offset: +${toString cfg.clockOffset} MHz...")
        info = c_nvmlClockOffset_t()
        info.version = nvmlClockOffset_v1
        info.type = NVML_CLOCK_GRAPHICS
        info.pstate = NVML_PSTATE_0  # Performance state 0 (maximum performance state)
        info.clockOffsetMHz = ${toString cfg.clockOffset}

        nvmlDeviceSetClockOffsets(device, byref(info))

        print("NVIDIA GPU undervolt settings applied successfully!")

    except Exception as e:
        print(f"Error applying NVIDIA undervolt settings: {e}")
        sys.exit(1)
    finally:
        # Always cleanup NVML
        try:
            nvmlShutdown()
        except:
            pass
  '';
in {
  # ═════════════════════════════════════════════════════════════════════════
  # MODULE OPTIONS
  # ═════════════════════════════════════════════════════════════════════════

  options.services.nvidia-undervolt = {
    enable = mkEnableOption "NVIDIA GPU undervolting service";

    gpuIndex = mkOption {
      type = types.int;
      default = 0;
      description = "Index of the GPU device to undervolt (0 for first GPU)";
    };

    minClock = mkOption {
      type = types.int;
      default = 210;
      description = ''
        Minimum GPU clock speed in MHz.
        Lower values save more power but may reduce performance.
        Default 210 MHz is conservative for idle/light workloads.
      '';
    };

    maxClock = mkOption {
      type = types.int;
      default = 1815;
      description = ''
        Maximum GPU clock speed in MHz.
        Prevents GPU from boosting to stock speeds.
        Example: RTX 3060 stock boost ~1.9GHz, limiting to 1815 MHz saves power.
      '';
    };

    powerLimit = mkOption {
      type = types.int;
      default = 280000;
      description = ''
        Power management limit in milliwatts (mW).
        280000 mW = 280W
        Example: RTX 3060 TDP is ~170W, setting to 280W provides headroom.
        Lower values = less power consumption but may throttle performance.
      '';
    };

    clockOffset = mkOption {
      type = types.int;
      default = 120;
      description = ''
        Graphics clock offset in MHz (added to base clock).
        Positive values increase performance slightly within locked clock range.
        Use 0 if you want pure undervolting without any overclock offset.
      '';
    };

    package = mkOption {
      type = types.package;
      default = undervoltScript;
      description = "Package containing the undervolt script";
    };
  };

  # ═════════════════════════════════════════════════════════════════════════
  # MODULE CONFIGURATION
  # ═════════════════════════════════════════════════════════════════════════

  config = mkIf cfg.enable {
    # Safety check: Ensure NVIDIA drivers are loaded
    assertions = [{
      assertion = config.services.xserver.videoDrivers != [ ]
        -> (builtins.elem "nvidia" config.services.xserver.videoDrivers);
      message =
        "NVIDIA undervolt service requires NVIDIA drivers to be enabled";
    }];

    # Make script available system-wide for manual testing
    environment.systemPackages = [ cfg.package pythonWithPynvml ];

    # Enable nvidia-persistenced (required for settings to persist)
    # Keeps GPU driver loaded so settings don't reset when apps close
    hardware.nvidia.nvidiaPersistenced = true;

    # ═══════════════════════════════════════════════════════════════════════
    # PRIMARY SERVICE - Apply undervolt on boot
    # ═══════════════════════════════════════════════════════════════════════
    systemd.services.nvidia-undervolt = {
      description = "Undervolt NVIDIA GPU device";
      # Wait for GPU to be fully initialized
      after = [
        "graphical.target"
        "nvidia-persistenced.service"
        "multi-user.target"
      ];
      wants = [ "nvidia-persistenced.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = "root"; # Requires root for GPU control
        ExecStart = "${cfg.package}/bin/undervolt-nvidia-device";
        RemainAfterExit = true; # Keep service "active" after running
        Restart = "on-failure";
        RestartSec = "30";
        # Wait 5 seconds for GPU to be fully ready
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
      };

      # Only run if NVIDIA GPU is detected
      unitConfig = { ConditionPathExists = "/dev/nvidia0"; };
    };

    # ═══════════════════════════════════════════════════════════════════════
    # RESUME SERVICE - Re-apply undervolt after suspend/hibernate
    # ═══════════════════════════════════════════════════════════════════════
    # GPU settings are lost when system suspends, need to re-apply on wake
    systemd.services.nvidia-undervolt-resume = {
      description = "Re-apply NVIDIA GPU undervolt after resume";
      after = [
        "systemd-suspend.service"
        "systemd-hibernate.service"
        "nvidia-resume.service"
      ];
      wantedBy = [ "suspend.target" "hibernate.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = pkgs.writeShellScript "nvidia-undervolt-resume" ''
          # Wait for GPU to be ready after resume (hardware initialization)
          sleep 10
          # Re-apply undervolt settings
          ${cfg.package}/bin/undervolt-nvidia-device
        '';
      };

      # Only run if NVIDIA GPU is detected
      unitConfig = { ConditionPathExists = "/dev/nvidia0"; };
    };
  };
}

# ═══════════════════════════════════════════════════════════════════════════
# USAGE INSTRUCTIONS
# ═══════════════════════════════════════════════════════════════════════════
#
# 1. Enable in your configuration:
#    services.nvidia-undervolt.enable = true;
#
# 2. Optional: Customize settings (example for RTX 3060):
#    services.nvidia-undervolt = {
#      enable = true;
#      minClock = 210;      # Minimum clock (idle)
#      maxClock = 1815;     # Maximum clock (under load)
#      powerLimit = 170000; # 170W power limit (stock TDP)
#      clockOffset = 0;     # No overclock offset (pure undervolt)
#    };
#
# 3. Deploy:
#    sudo nixos-rebuild switch
#
# 4. Verify settings applied:
#    nvidia-smi -q -d CLOCK
#    nvidia-smi -q -d POWER
#
# 5. Test manually (if needed):
#    sudo undervolt-nvidia-device
#
# FINDING YOUR GPU'S SAFE VALUES:
# - Check stock specs: nvidia-smi
# - Start conservative (higher clocks, higher power)
# - Lower values gradually while testing stability
# - Monitor temps: watch -n 1 nvidia-smi
#
# ═══════════════════════════════════════════════════════════════════════════

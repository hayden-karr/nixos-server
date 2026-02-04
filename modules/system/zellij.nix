{ pkgs, ... }:

# Zellij Terminal Multiplexer (system-level)
# Package install and SSH auto-start (user config in admin/zellij.nix)

{
  environment.systemPackages = with pkgs; [ zellij ];

  # Auto-start zellij on SSH connections
  environment.etc."profile.local".text = ''
    export TERM=xterm-256color

    case $- in
      *i*)
        if [ -n "$SSH_CONNECTION" ] && [ -z "$ZELLIJ" ]; then
          exec zellij
        fi
        ;;
    esac
  '';
}

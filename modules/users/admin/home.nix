{ ... }: {
  # Home Manager configuration for admin user
  # Admin user manages the system but does NOT run application containers
  # Application containers run under dedicated user accounts for security isolation

  # User environment configuration
  home = { stateVersion = "25.05"; };

  # Import optional configurations
  imports = [
    ./git.nix # Git config
    #   ./zellij.nix # Terminal multiplexer config
  ];
}

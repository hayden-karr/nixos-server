{
  description = "Minimal hardened modular server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, sops-nix, home-manager, ... }: {
    nixosConfigurations.server = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        sops-nix.nixosModules.sops
        ./modules

        # Home Manager integration - Per-user configs for security isolation
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "bakup";

            # Each user gets their own home-manager config
            # This ensures proper isolation - containers run in their own user namespaces
            users = {
              admin = import ./modules/users/admin/home.nix;
              minecraft = import ./modules/users/minecraft/home.nix;
              immich-friend = import ./modules/users/immich-friend/home.nix;
            };
          };
        }
      ];
    };

    # Deployment helpers
    apps.x86_64-linux = {
      # Deploy from local repo (development workflow)
      deploy = {
        type = "app";
        program = toString
          (nixpkgs.legacyPackages.x86_64-linux.writeShellScript "deploy" ''
            #!/usr/bin/env bash
            set -e

            SERVER_HOST=''${SERVER_HOST:-sillysharks}

            NIX_SSHOPTS="-F $HOME/.ssh/config" \
              nixos-rebuild switch --flake .#server \
              --target-host "$SERVER_HOST" \
              --build-host ""

            echo "Deployment complete!"
          '');
        meta = {
          description = "Deploy configuration to server from local repository";
        };
      };

      # Test deployment (build and test, but don't activate)
      test = {
        type = "app";
        program = toString
          (nixpkgs.legacyPackages.x86_64-linux.writeShellScript "test" ''
            set -e

            SERVER_HOST=''${SERVER_HOST:-sillysharks}

            NIX_SSHOPTS="-F $HOME/.ssh/config" \
              nixos-rebuild test --flake .#server \
              --target-host "$SERVER_HOST" \
              --build-host ""

            echo "Test deployment complete! (Changes active until reboot)"
          '');
        meta = {
          description =
            "Test configuration deployment without activating boot entry";
        };
      };

      # Dry run (build only, don't deploy)
      build = {
        type = "app";
        program = toString
          (nixpkgs.legacyPackages.x86_64-linux.writeShellScript "build" ''
            set -e

            echo "Building configuration..."
            nixos-rebuild build --flake .#server

            echo "Build complete! (Not deployed)"
          '');
        meta = {
          description = "Build configuration locally without deploying";
        };
      };

      check = {
        type = "app";
        program = toString
          (nixpkgs.legacyPackages.x86_64-linux.writeShellScript "check" ''
            	set -e

              echo "Checking configuration..."
              nix flake check 2>&1

            	echo "Check complete!"
          '');
        meta = { description = "Check flake configuration for errors"; };
      };

      # Deploy from GitHub (production workflow)
      # Server pulls config directly from GitHub
      deploy-github = {
        type = "app";
        program = toString (nixpkgs.legacyPackages.x86_64-linux.writeShellScript
          "deploy-github" ''
            set -e

            SERVER_HOST=''${SERVER_HOST:-admin@sillysharks}
            # REPLACE with your GitHub username/repo
            GITHUB_REPO=''${GITHUB_REPO:-YOUR-USERNAME/nixos-server}


            ssh "$SERVER_HOST" "
              set -e
              echo 'Pulling latest config from GitHub...'
              doas nixos-rebuild switch --flake github:$GITHUB_REPO#server
              echo 'Server updated from GitHub!'
            "
          '');
        meta = {
          description = "Deploy to server by pulling configuration from GitHub";
        };
      };
    };
  };
}


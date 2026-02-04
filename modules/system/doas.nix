_:

# doas - sudo replacement (simpler, more secure)

{
  security.sudo.enable = false;

  security.doas = {
    enable = true;
    extraRules = [{
      groups = [ "wheel" ];
      keepEnv = true;
      persist = true; # Keep auth for 5 minutes per session
      noPass =
        false; # no password input needed. INSECURE - should disable for production, use only for testing
    }];
  };

  environment.shellAliases = { sudo = "doas"; };
}


_:

{
  # Ollama - Local AI/LLM Server with CUDA acceleration
  # Run large language models locally (Llama, Mistral, etc.)
  #
  # Access:
  # - Web UI: https://ai.local (via VPN or LAN)
  # - API: https://ai.local/api
  #
  # Models stored on SSD for performance

  services.ollama = {
    enable = true;
    acceleration = "cuda"; # NVIDIA GPU acceleration

    # Listen on all interfaces for network access
    host = "0.0.0.0";
    port = 11434;

    # Store models on SSD for fast loading
    models = "/mnt/ssd/ollama/models";

    # Disable telemetry
    environmentVariables = { OLLAMA_TELEMETRY = "false"; };
  };

  # Open WebUI - ChatGPT-like interface for Ollama
  virtualisation.oci-containers.containers.open-webui = {
    image = "ghcr.io/open-webui/open-webui:main";
    autoStart = true;

    ports = [ "8088:8088" ];

    volumes = [ "/mnt/ssd/ollama/open-webui:/app/backend/data" ];

    environment = {
      # Access Ollama on host via host.containers.internal
      OLLAMA_BASE_URL = "http://host.containers.internal:11434";
      WEBUI_NAME = "AI Server";
      WEBUI_AUTH = "true"; # Require login
      PORT = "8088";
    };
  };

  # Ollama service runs as ollama user (created by NixOS ollama module)
  systemd.tmpfiles.rules = [
    # Parent directory - wide permissions so ollama service can access
    "d /mnt/ssd/ollama 0755 root root -"
    # Models directory - wide permissions for ollama service
    "d /mnt/ssd/ollama/models 0777 root root -"
    "z /mnt/ssd/ollama/models 0777 root root -"
    # Open WebUI data
    "d /mnt/ssd/ollama/open-webui 0755 root root -"
  ];

  # Ensure Open WebUI starts after Ollama
  systemd.services."podman-open-webui" = { after = [ "ollama.service" ]; };

  # SETUP INSTRUCTIONS:
  #
  # 1. Deploy configuration:
  #    nix run .#deploy
  #
  # 2. Download models (on the server):
  #    ollama pull llama3.2       # Fast, good for chat (3B model, ~4GB RAM)
  #    ollama pull mistral        # Balanced quality (7B model, ~8GB RAM)
  #    ollama pull codellama      # Code-specialized (7B model, ~8GB RAM)
  #
  # 3. Access via browser:
  #    - https://ai.local (VPN or LAN)
  #    - First visit: Create an account (stored locally)
  #    - Start chatting
  #
  # 4. API access (optional):
  #    curl https://ai.local/api/generate -d '{
  #      "model": "llama3.2",
  #      "prompt": "Explain NixOS in simple terms"
  #    }'
  #
  # NOTES:
  # - Models cached in /mnt/ssd/ollama/models (4GB+ each)
  # - First inference loads model into VRAM (slow), subsequent runs fast
  # - CUDA acceleration uses NVIDIA GPU
  # - All processing local
}

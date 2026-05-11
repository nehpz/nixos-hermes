{ config, lib, pkgs, ... }:

let
  cfg = config.services.hindsightMemory;
in
{
  config = lib.mkIf cfg.enable {
    systemd.services.llama-server = {
      description = "llama.cpp inference server (Gemma 4 E2B Q6_K_L)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = "hermes";
        StateDirectory = "hermes";
        Restart = "on-failure";
        RestartSec = "5s";
        ExecStartPre = pkgs.writeShellScript "llama-server-precheck" ''
          if [ ! -f /var/lib/hermes/models/google_gemma-4-E2B-it-Q6_K_L.gguf ]; then
            echo "ERROR: model file not found at /var/lib/hermes/models/google_gemma-4-E2B-it-Q6_K_L.gguf"
            echo "Run Task 1 from the hindsight-memory-provider plan to download it."
            exit 1
          fi
        '';
        ExecStart = ''
          ${pkgs.llama-cpp}/bin/llama-server \
            --model /var/lib/hermes/models/google_gemma-4-E2B-it-Q6_K_L.gguf \
            --host 127.0.0.1 \
            --port 8080 \
            --ctx-size 8192 \
            --threads 10 \
            --chat-template gemma
        '';
      };
    };
  };
}

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.hindsightMemory;
  llama = cfg.llama;
  types = lib.types;

  modelName = builtins.baseNameOf llama.modelPath;
  llamaArgs = [
    "--model"
    llama.modelPath
    "--host"
    llama.host
    "--port"
    (toString llama.port)
    "--ctx-size"
    (toString llama.contextSize)
    "--threads"
    (toString llama.threads)
  ]
  ++ lib.optionals llama.enableEmbeddings (
    [ "--embeddings" ]
    ++ lib.optionals (llama.pooling != null) [
      "--pooling"
      llama.pooling
    ]
  )
  ++ lib.optionals (llama.chatTemplate != null) [
    "--chat-template"
    llama.chatTemplate
  ];
in
{
  options.services.hindsightMemory.llama = {
    enable = lib.mkEnableOption "local llama.cpp inference server for Hindsight memory";

    modelPath = lib.mkOption {
      type = types.str;
      default = "/var/lib/hermes/models/google_gemma-4-E2B-it-Q6_K_L.gguf";
      description = "Absolute path to the GGUF model served by llama.cpp.";
    };

    host = lib.mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address for llama.cpp's OpenAI-compatible HTTP server.";
    };

    port = lib.mkOption {
      type = types.port;
      default = 8080;
      description = "TCP port for llama.cpp's OpenAI-compatible HTTP server.";
    };

    contextSize = lib.mkOption {
      type = types.ints.positive;
      default = 8192;
      description = "Context size passed to llama.cpp.";
    };

    threads = lib.mkOption {
      type = types.ints.positive;
      default = 10;
      description = "CPU threads passed to llama.cpp.";
    };

    enableEmbeddings = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Whether to enable llama.cpp's OpenAI-compatible /v1/embeddings endpoint.";
    };

    pooling = lib.mkOption {
      type = types.nullOr (
        types.enum [
          "mean"
          "cls"
          "last"
          "rank"
        ]
      );
      default = "mean";
      description = "Pooling mode used by llama.cpp when embeddings are enabled.";
    };

    chatTemplate = lib.mkOption {
      type = types.nullOr types.str;
      default = "gemma";
      description = "Chat template passed to llama.cpp; set to null to let llama.cpp infer it.";
    };
  };

  config = lib.mkIf llama.enable {
    systemd.tmpfiles.rules = [
      "d /var/lib/hermes/models 0755 hermes hermes - -"
    ];

    systemd.services.llama-server = {
      description = "llama.cpp inference server (${modelName})";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = "hermes";
        StateDirectory = "hermes";
        Restart = "on-failure";
        RestartSec = "5s";
        ExecStartPre = pkgs.writeShellScript "llama-server-precheck" ''
          if [ ! -f ${lib.escapeShellArg llama.modelPath} ]; then
            echo "ERROR: model file not found at ${llama.modelPath}"
            echo "Place the Gemma GGUF at services.hindsightMemory.llama.modelPath or override that option."
            exit 1
          fi
        '';
        ExecStart = lib.escapeShellArgs ([ "${pkgs.llama-cpp}/bin/llama-server" ] ++ llamaArgs);
      };
    };
  };
}

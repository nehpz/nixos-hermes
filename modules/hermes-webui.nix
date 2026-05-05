{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:

let
  cfg = config.services.hermes-webui;

  # hermes-webui source - only new fetchFromGitHub in this module
  webui-src = pkgs.fetchFromGitHub {
    owner = "nesquena";
    repo = "hermes-webui";
    rev = "master";
    hash = "sha256-7zUDGCWNC/whuC4V79E3Nye+J0/M8ehTN75EWArGx2s=";
  };

  # hermes-agent package and source files
  hermes-pkg = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;
  hermes-venv-python = "${hermes-pkg.hermesVenv}/bin/python3";
  hermes-agent-src = hermes-pkg.outPath;

  # Build python path for run_agent
  # Prepend so it wins for those names (absent from venv site-packages).
  hermes-venv-sp = "${hermes-pkg.hermesVenv}/${pkgs.python312.sitePackages}";
  python-path = "${hermes-agent-src}:${hermes-venv-sp}";

  # Write env vars to a file - avoids systemd Environment attrset thunk issue.
  # systemd EnvironmentFile format: one "KEY=VALUE" per line.
  envFile = pkgs.writeText "hermes-webui.env" (
    lib.concatStringsSep "\n" [
      "HERMES_WEBUI_HOST=127.0.0.1"
      "HERMES_WEBUI_PORT=${toString cfg.port}"
      "HERMES_WEBUI_STATE_DIR=${cfg.stateDir}"
      "HERMES_WEBUI_AGENT_DIR=${hermes-agent-src}"
      "HERMES_HOME=/var/lib/hermes"
      "PYTHONPATH=${python-path}"
    ]
    + "\n"
  );
in
{
  options.services.hermes-webui = {
    enable = lib.mkEnableOption "hermes-webui";
    port = lib.mkOption {
      default = 8787;
      type = lib.types.port;
    };
    stateDir = lib.mkOption {
      default = "/var/lib/hermes/webui";
      type = lib.types.path;
    };
    password = lib.mkOption {
      default = null;
      type = lib.types.nullOr lib.types.str;
      description = "Path to sops secret file containing HERMES_WEBUI_PASSWORD.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.hermes-webui = {
      description = "Hermes webui";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = "hermes";
        Group = "hermes";
        Restart = "always";
        RestartSec = "5";

        # Systemd automatically creates and permissions /var/lib/hermes/webui
        StateDirectory = "hermes/webui";

        ExecStart = lib.concatStringsSep " " [
          hermes-venv-python
          "${webui-src}/server.py"
        ];

        # Environment vars via file (avoids systemd Environment attrset thunk coercion issue)
        # Optional password auth via sops
        EnvironmentFile = [ envFile ] ++ lib.optionals (cfg.password != null) [ cfg.password ];

        # Hardening
        ProtectSystem = "strict";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
  };
}

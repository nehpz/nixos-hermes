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
    rev = "d8cd5567e0e23b5e81c59679eb117b83d2e9a0c6";
    hash = "sha256-7zUDGCWNC/whuC4V79E3Nye+J0/M8ehTN75EWArGx2s=";
  };

  # hermes-agent package and source files
  hermes-pkg = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;
  hermes-venv-python = "${hermes-pkg.hermesVenv}/bin/python3";
  hermes-agent-src = hermes-pkg.outPath;

  # Build python path for run_agent. Keep site-packages first so vendored pip
  # packages never shadow Nix-provided dependencies.
  hermes-venv-sp = "${hermes-pkg.hermesVenv}/${pkgs.python3.sitePackages}";
  python-path = "${hermes-venv-sp}:${webui-src}:${hermes-agent-src}";

  startScript = pkgs.writeShellScript "hermes-webui-start" ''
    set -eu
    if [ -n "''${CREDENTIALS_DIRECTORY:-}" ] && [ -f "$CREDENTIALS_DIRECTORY/password" ]; then
      export HERMES_WEBUI_PASSWORD="$(cat "$CREDENTIALS_DIRECTORY/password")"
    fi
    exec ${hermes-venv-python} ${webui-src}/server.py
  '';

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
      description = "Path to sops secret file containing the raw webui password.";
    };
  };

  config = {
    services.hermes-webui = {
      enable = true;
      password = config.sops.secrets."hermes-webui".path;
    };

    systemd.services.hermes-webui = lib.mkIf cfg.enable {
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

        ExecStart = startScript;

        # Environment vars via file (avoids systemd Environment attrset thunk coercion issue).
        # Password is a raw sops secret, so pass it as a systemd credential and
        # let the wrapper export HERMES_WEBUI_PASSWORD.
        EnvironmentFile = [ envFile ];
        LoadCredential = lib.optionals (cfg.password != null) [ "password:${cfg.password}" ];

        # Hardening
        ProtectSystem = "strict";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
  };
}

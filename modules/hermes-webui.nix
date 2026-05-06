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

  # hermes-agent package and source files. Use the configured package so this
  # module follows any future services.hermes-agent.package override, and use
  # the flake input outPath for the source tree expected by hermes-webui.
  hermes-pkg = config.services.hermes-agent.package;
  hermes-venv-python = "${hermes-pkg.passthru.hermesVenv}/bin/python3";
  hermes-agent-src = inputs.hermes-agent.outPath;

  # The ExecStart interpreter is already hermesVenv Python, so it supplies its
  # own site-packages. PYTHONPATH only needs source trees for webui api/* and
  # hermes-agent's lazy run_agent imports.
  python-path = "${webui-src}:${hermes-agent-src}";

  settingsPatchScript = pkgs.writeText "hermes-webui-settings.py" ''
    import json
    from pathlib import Path

    settings_path = Path("${cfg.stateDir}") / "settings.json"
    settings = {}
    if settings_path.exists():
        try:
            content = settings_path.read_text(encoding="utf-8")
            if content.strip():
                loaded = json.loads(content)
                if not isinstance(loaded, dict):
                    raise ValueError("settings.json must contain an object")
                settings = loaded
        except Exception:
            # Preserve a corrupt or unexpected settings file rather than
            # overwriting user preferences with a partial replacement.
            raise SystemExit(0)
    if settings.get("show_cli_sessions") is not True:
        settings["show_cli_sessions"] = True
        settings_path.write_text(json.dumps(settings, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
  '';

  startScript = pkgs.writeShellScript "hermes-webui-start" ''
    set -eu
    if [ -n "''${CREDENTIALS_DIRECTORY:-}" ] && [ -f "$CREDENTIALS_DIRECTORY/password" ]; then
      export HERMES_WEBUI_PASSWORD="$(cat "$CREDENTIALS_DIRECTORY/password")"
    fi
    ${pkgs.python3}/bin/python3 ${settingsPatchScript}
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
      "HERMES_HOME=/var/lib/hermes/.hermes"
      "HERMES_BASE_HOME=/var/lib/hermes/.hermes"
      "HERMES_KANBAN_HOME=/var/lib/hermes/.hermes"
      "HERMES_KANBAN_DB=/var/lib/hermes/.hermes/kanban.db"
      "HERMES_KANBAN_WORKSPACES_ROOT=/var/lib/hermes/.hermes/kanban/workspaces"
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
      readOnly = true;
      default = "/var/lib/hermes/webui";
      type = lib.types.path;
      description = "Systemd-managed state directory for hermes-webui.";
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

        # Hardening. Keep the filesystem read-only by default, but allow
        # hermes-webui to manage profiles, settings, sessions, and credentials
        # under HERMES_HOME.
        ProtectSystem = "strict";
        ReadWritePaths = [ "/var/lib/hermes" ];
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
  };
}

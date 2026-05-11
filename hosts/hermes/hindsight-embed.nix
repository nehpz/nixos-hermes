{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.hindsightMemory;

  # Use the configured Hermes package's sealed runtime Python instead of a
  # fixed /nix/store path. This follows any future services.hermes-agent.package
  # override and avoids coupling this host module to one Hermes build output.
  hermesEnvPython = "${config.services.hermes-agent.package.passthru.hermesVenv}/bin/python3";

  # Writable venv path. Created at service start by ExecStartPre.
  # Uses --system-site-packages so hermes-agent-env packages are visible, while
  # the EnvironmentFile below puts the Nix-patched Hermes site-packages first.
  # That keeps binary packages like numpy/scipy on their NixOS-patchelf builds
  # even if Hindsight's pip dependency resolver drops wheels into the venv.
  # Shared with the temporary opusCtypesShim in modules/packages.nix so Hermes can
  # import hindsight-client during the spike. This is deliberately host-stateful;
  # ONE-24 should remove the cross-module coupling when the provider wiring is finalized.
  hindsightVenv = "/var/lib/hermes/.venv";
  hermesVenv = config.services.hermes-agent.package.passthru.hermesVenv;
  # Discover the Hermes sealed venv's Python minor version from the venv itself.
  # Do not use pkgs.python3.pythonVersion here: this host's nixpkgs Python is
  # 3.13 while the locked Hermes venv is currently Python 3.12.
  hermesPythonDirs = builtins.filter (name: lib.hasPrefix "python" name) (
    builtins.attrNames (builtins.readDir "${hermesVenv}/lib")
  );
  hermesPythonDir =
    if hermesPythonDirs == [ ] then
      throw "Hermes venv at ${hermesVenv} has no lib/python* site-packages directory"
    else
      builtins.head hermesPythonDirs;
  hermesSitePackages = "${hermesVenv}/lib/${hermesPythonDir}/site-packages";

  serviceEnvFile = pkgs.writeText "hindsight-embed.env" (
    lib.concatStringsSep "\n" [
      "PYTHONPATH=${pkgs.opusCtypesShim}:${hermesSitePackages}"
      "HINDSIGHT_API_LLM_PROVIDER=openai"
      "HINDSIGHT_API_LLM_API_KEY=local"
      "HINDSIGHT_API_LLM_BASE_URL=http://${cfg.llama.host}:${toString cfg.llama.port}/v1"
      "HINDSIGHT_API_LLM_MODEL=${builtins.baseNameOf cfg.llama.modelPath}"
      "HINDSIGHT_API_DATABASE_URL=postgresql:///hermes?host=/run/postgresql"
      "HINDSIGHT_API_EMBEDDINGS_PROVIDER=openai"
      "HINDSIGHT_API_EMBEDDINGS_OPENAI_API_KEY=local"
      "HINDSIGHT_API_EMBEDDINGS_OPENAI_BASE_URL=http://${cfg.llama.host}:${toString cfg.llama.port}/v1"
      "HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL=${builtins.baseNameOf cfg.llama.modelPath}"
      # Avoid the default local sentence-transformers reranker; the spike uses
      # Hindsight's dependency-free RRF passthrough until ONE-24 wires a richer
      # provider intentionally.
      "HINDSIGHT_API_RERANKER_PROVIDER=rrf"
      "HINDSIGHT_API_PORT=8888"
      "HINDSIGHT_API_HOST=127.0.0.1"
    ]
    + "\n"
  );

  setupScript = pkgs.writeShellScript "hindsight-embed-setup" ''
    set -euo pipefail
    VENV="${hindsightVenv}"
    PYTHON="${hermesEnvPython}"

    # Recreate the venv when Hermes' sealed Python changes after a NixOS rebuild.
    if [ ! -f "$VENV/bin/python3" ] || [ "$(readlink -f "$VENV/bin/python3")" != "$(readlink -f "$PYTHON")" ]; then
      echo "Creating/refreshing hindsight venv at $VENV..."
      "$PYTHON" -m venv --system-site-packages --clear "$VENV"
    fi

    # Install/upgrade hindsight packages into the venv.
    # --system-site-packages means hermes-agent-env packages are inherited;
    # only packages absent from the env are installed here. Exact pins and
    # --no-cache avoid unbounded cache growth and reduce spike nondeterminism.
    echo "Installing hindsight packages..."
    ${pkgs.uv}/bin/uv --no-cache pip install \
      --python "$VENV/bin/python3" \
      --quiet \
      "hindsight-api-slim==0.5.4" \
      "hindsight-client==0.5.4" \
      "hindsight-embed==0.5.4"
    echo "hindsight packages ready."
  '';

in
{
  options.services.hindsightMemory.enable = lib.mkEnableOption "local Hindsight memory spike services";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.llama.enable;
        message = "services.hindsightMemory currently uses the local llama.cpp OpenAI-compatible endpoint; set services.hindsightMemory.llama.enable = true or teach hindsight-embed.nix about an external provider.";
      }
    ];

    # Postgres instance for hindsight-embed's backing store.
    # hindsight-embed (hindsight-api) manages its own schema; we just provide the server.
    services.postgresql = {
      enable = true;
      # NixOS requires that a database with the same name as the user exists when
      # ensureDBOwnership = true. We therefore name the database after the user
      # ("hermes") and connect over the local Unix socket as the hermes service user.
      # Hindsight stores embeddings with pgvector.
      extensions = ps: [ ps.pgvector ];
      ensureDatabases = [ "hermes" ];
      ensureUsers = [
        {
          name = "hermes";
          ensureDBOwnership = true;
        }
      ];
    };

    systemd.services.hindsight-postgres-init = {
      description = "Initialize Hindsight PostgreSQL extensions";
      after = [ "postgresql.service" ];
      before = [ "hindsight-embed.service" ];
      requiredBy = [ "hindsight-embed.service" ];
      requires = [ "postgresql.service" ];

      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        ExecStart = "${config.services.postgresql.package}/bin/psql -d hermes -c 'CREATE EXTENSION IF NOT EXISTS vector;'";
      };
    };

    systemd.services.hindsight-embed = {
      description = "Hindsight memory server (hindsight-api, local_external mode)";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "postgresql.service"
        "hindsight-postgres-init.service"
      ]
      ++ lib.optionals cfg.llama.enable [ "llama-server.service" ];
      requires = [
        "postgresql.service"
        "hindsight-postgres-init.service"
      ]
      ++ lib.optionals cfg.llama.enable [ "llama-server.service" ];

      serviceConfig = {
        Type = "simple";
        User = "hermes";
        StateDirectory = "hermes";
        Restart = "on-failure";
        RestartSec = "5s";
        EnvironmentFile = [ serviceEnvFile ];
        ExecStartPre = setupScript;
        # Run hindsight-api directly in foreground (no --daemon flag).
        # systemd manages the lifecycle; daemon mode would fork away and break Type=simple.
        ExecStart = "${hindsightVenv}/bin/hindsight-api --host 127.0.0.1 --port 8888";
      };
    };
  };
}

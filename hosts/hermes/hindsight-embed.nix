{ pkgs, ... }:

let
  # Python interpreter used by the hermes-agent-env. This must stay in sync with
  # the hermes-agent package version. If hermes-agent updates and changes its Python
  # version, update this path AND the sys.path version string in modules/packages.nix to match.
  hermesEnvPython = "/nix/store/pfhlzs9bs9xwbvcnw0xc16vwaxz5xvxd-hermes-agent-env/bin/python3";

  # Writable venv path. Created at activation time by ExecStartPre.
  # Uses --system-site-packages so hermes-agent-env packages (numpy, etc.) are
  # inherited with their NixOS patchelf rpath — pip-installed copies would break.
  hindsightVenv = "/var/lib/hermes/.venv";

  setupScript = pkgs.writeShellScript "hindsight-embed-setup" ''
    set -euo pipefail
    VENV="${hindsightVenv}"
    PYTHON="${hermesEnvPython}"

    # Create the venv only if it doesn't exist
    if [ ! -f "$VENV/bin/python3" ]; then
      echo "Creating hindsight venv at $VENV..."
      "$PYTHON" -m venv --system-site-packages "$VENV"
    fi

    # Install/upgrade hindsight packages into the venv.
    # --system-site-packages means hermes-agent-env packages are inherited;
    # only packages absent from the env are installed here.
    echo "Installing hindsight packages..."
    ${pkgs.uv}/bin/uv pip install \
      --python "$VENV/bin/python3" \
      --quiet \
      "hindsight-client>=0.5.4" \
      "hindsight-embed>=0.5.4" \
      "sentence-transformers>=3.0.0" \
      "huggingface-hub>=1.5.0,<2.0"
    echo "hindsight packages ready."
  '';

in
{
  # Postgres instance for hindsight-embed's backing store.
  # hindsight-embed (hindsight-api) manages its own schema; we just provide the server.
  services.postgresql = {
    enable = true;
    # NixOS requires that a database with the same name as the user exists when
    # ensureDBOwnership = true. We therefore name the database after the user
    # ("hermes") and point HINDSIGHT_API_DATABASE_URL at it.
    ensureDatabases = [ "hermes" ];
    ensureUsers = [
      {
        name = "hermes";
        ensureDBOwnership = true;
      }
    ];
  };

  systemd.services.hindsight-embed = {
    description = "Hindsight memory server (hindsight-api, local_external mode)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "postgresql.service"
      "llama-server.service"
    ];
    requires = [ "postgresql.service" ];

    # Environment variables for hindsight-api.
    # API key is set to "local" — llama.cpp server does not check it.
    # Model ID filled after llama-server is running and /v1/models is queried (Step 12).
    environment = {
      HINDSIGHT_API_LLM_PROVIDER = "openai";
      HINDSIGHT_API_LLM_API_KEY = "local"; # llama-server requires non-empty but ignores value
      HINDSIGHT_API_LLM_BASE_URL = "http://127.0.0.1:8080/v1";
      HINDSIGHT_API_LLM_MODEL = "google_gemma-4-E2B-it-Q6_K_L.gguf";
      HINDSIGHT_API_DATABASE_URL = "postgresql://hermes@localhost/hermes";
      HINDSIGHT_API_PORT = "8888";
      HINDSIGHT_API_HOST = "127.0.0.1";
    };

    serviceConfig = {
      Type = "simple";
      User = "hermes";
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStartPre = setupScript;
      # Run hindsight-api directly in foreground (no --daemon flag).
      # systemd manages the lifecycle; daemon mode would fork away and break Type=simple.
      ExecStart = "${hindsightVenv}/bin/hindsight-api --host 127.0.0.1 --port 8888";
    };
  };
}

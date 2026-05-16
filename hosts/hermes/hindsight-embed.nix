{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.hindsightMemory;
  types = lib.types;

  # Use the configured Hermes package's sealed runtime Python instead of a
  # fixed /nix/store path. This follows any future services.hermes-agent.package
  # override and avoids coupling this host module to one Hermes build output.
  hermesEnvPython = "${config.services.hermes-agent.package.passthru.hermesVenv}/bin/python3";

  # Writable Hindsight API venv path. Created at service start by ExecStartPre.
  # This venv belongs to hindsight-embed.service itself. Agent-facing Hermes
  # imports `hindsight_client` from services.hermes-agent.extraPythonPackages,
  # not by adding this mutable venv to the Hermes service PYTHONPATH.
  hindsightVenv = "/var/lib/hermes/.venv";

  serviceEnvFile = pkgs.writeText "hindsight-embed.env" (
    lib.concatStringsSep "\n" [
      "LD_LIBRARY_PATH=${pkgs.stdenv.cc.cc.lib}/lib"
      "HINDSIGHT_API_LLM_PROVIDER=${cfg.llm.provider}"
      "HINDSIGHT_API_LLM_BASE_URL=${cfg.llm.baseUrl}"
      "HINDSIGHT_API_LLM_MODEL=${cfg.llm.model}"
      # Hindsight's retain prompt is schema-heavy; keep a generous timeout for
      # remote proxy retries while relying on a stronger model than local CPU llama.cpp.
      "HINDSIGHT_API_LLM_TIMEOUT=${toString cfg.llm.timeout}"
      "HINDSIGHT_API_RETAIN_MAX_COMPLETION_TOKENS=4096"
      "HINDSIGHT_API_RETAIN_EXTRACTION_MODE=custom"
      ''HINDSIGHT_API_RETAIN_CUSTOM_INSTRUCTIONS=Return exactly one JSON object with a top-level "facts" array; never return a bare array. Extract only durable personal, preference, role, project, and operational facts useful across future sessions. Do not extract transient command attempts, retry counts, curl invocations, timeouts, or debugging steps as facts. If a sentence contains both transient steps and a durable lesson, extract only the durable lesson. Use fact_type="world" for facts about people, organizations, preferences, roles, projects, tools, or external state. Use fact_type="assistant" only for first-person actions performed by the narrator/assistant. For each fact include what, when, where, who, why, fact_type, fact_kind, and entities.''
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

  llmPreflightPython = pkgs.writeText "hindsight-llm-preflight.py" ''
    import json
    import os
    import sys
    import urllib.error
    import urllib.request

    base_url = os.environ["HINDSIGHT_API_LLM_BASE_URL"].rstrip("/")
    model = os.environ["HINDSIGHT_API_LLM_MODEL"]
    api_key = os.environ["HINDSIGHT_API_LLM_API_KEY"]
    models_url = f"{base_url}/models"

    request = urllib.request.Request(
        models_url,
        method="GET",
        headers={"Authorization": f"Bearer {api_key}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:500]
        raise SystemExit(f"Hindsight LLM preflight failed: HTTP {exc.code} from {models_url}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"Hindsight LLM preflight failed: connection error to {models_url}: {exc.reason}") from exc

    try:
        payload = json.loads(body)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Hindsight LLM preflight failed: invalid JSON from {models_url}: {body[:500]}") from exc

    if not isinstance(payload, dict):
        raise SystemExit(
            f"Hindsight LLM preflight failed: expected JSON object from {models_url}, "
            f"got {type(payload).__name__}"
        )

    data = payload.get("data") or []
    if not isinstance(data, list):
        raise SystemExit(
            f"Hindsight LLM preflight failed: expected JSON array at {models_url} data field, "
            f"got {type(data).__name__}"
        )

    model_ids = {str(item.get("id")) for item in data if isinstance(item, dict) and item.get("id")}
    if model not in model_ids:
        sample = ", ".join(sorted(model_ids)[:20])
        raise SystemExit(f"Missing configured Hindsight LLM model {model!r} from {models_url}; sample models: {sample}")

    print(f"Hindsight LLM preflight OK: {model} listed by {models_url}")
  '';

  recoveryPreflightScript = pkgs.writeShellScript "hindsight-embed-recovery-preflight" ''
    set -euo pipefail
    export HINDSIGHT_API_LLM_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/cliproxyapi-key")"

    # Release work claimed by a previous API/worker process before accepting
    # post-rebuild retain requests. This deployment runs a single Hindsight API
    # worker; revisit this if the database ever backs multiple live workers.
    if [ "$(${config.services.postgresql.package}/bin/psql "$HINDSIGHT_API_DATABASE_URL" -tAc "select to_regclass('public.async_operations')")" = "async_operations" ]; then
      ${hindsightVenv}/bin/python3 -m hindsight_api.admin.cli decommission-workers --yes
    fi

    # Fail fast before systemd marks the service started. The /models check
    # proves the OpenAI-compatible route, credential, and configured model, while
    # the outer timeout prevents a stuck dependency probe from greenwashing unit
    # startup with no API socket bound.
    ${pkgs.coreutils}/bin/timeout 15s ${hindsightVenv}/bin/python3 ${llmPreflightPython}
  '';

  startScript = pkgs.writeShellScript "hindsight-embed-start" ''
    set -euo pipefail
    export HINDSIGHT_API_LLM_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/cliproxyapi-key")"
    exec ${hindsightVenv}/bin/hindsight-api --host 127.0.0.1 --port 8888
  '';

  setupScript = pkgs.writeShellScript "hindsight-embed-setup" ''
    set -euo pipefail
    VENV="${hindsightVenv}"
    PYTHON="${hermesEnvPython}"
    PYTHON_MARKER="$VENV/.hermes-python"
    CURRENT_PYTHON="$(readlink -f "$PYTHON")"
    needs_install=0

    # Recreate the venv when Hermes' sealed Python changes after a NixOS rebuild.
    # A venv's bin/python3 resolves to the underlying CPython interpreter, not the
    # hermes-agent-env wrapper used to create it, so track the creator path in a
    # marker file instead of comparing readlink targets directly.
    if [ ! -f "$VENV/bin/python3" ] || [ ! -f "$PYTHON_MARKER" ] || [ "$(cat "$PYTHON_MARKER")" != "$CURRENT_PYTHON" ]; then
      echo "Creating/refreshing hindsight venv at $VENV..."
      "$PYTHON" -m venv --system-site-packages --clear "$VENV"
      printf '%s\n' "$CURRENT_PYTHON" > "$PYTHON_MARKER"
      needs_install=1
    fi

    # Avoid reinstalling wheels on every rebuild. The venv is mutable host state,
    # so exact version checks are enough to refresh only when pins change.
    if [ "$needs_install" -eq 0 ]; then
      "$VENV/bin/python3" -c 'from importlib.metadata import version; expected = {"hindsight-api-slim": "0.5.4", "hindsight-client": "0.5.4", "hindsight-embed": "0.5.4"}; raise SystemExit(0 if all(version(pkg) == want for pkg, want in expected.items()) else 1)' || needs_install=1
    fi

    if [ "$needs_install" -eq 1 ]; then
      echo "Installing hindsight packages..."
      ${pkgs.uv}/bin/uv --no-cache pip install \
        --python "$VENV/bin/python3" \
        --quiet \
        "hindsight-api-slim==0.5.4" \
        "hindsight-client==0.5.4" \
        "hindsight-embed==0.5.4"
      echo "hindsight packages ready."
    else
      echo "hindsight packages already at pinned versions."
    fi
  '';

in
{
  options.services.hindsightMemory = {
    enable = lib.mkEnableOption "local Hindsight memory spike services";

    llm = {
      provider = lib.mkOption {
        type = types.str;
        default = "openai";
        description = "Hindsight LLM provider name. Use openai for OpenAI-compatible proxies.";
      };

      baseUrl = lib.mkOption {
        type = types.str;
        default = "http://10.0.0.102:8317/v1";
        description = "OpenAI-compatible base URL used for Hindsight retain/reflect LLM calls.";
      };

      model = lib.mkOption {
        type = types.str;
        default = "gpt-5.4-mini";
        description = "Model used for Hindsight retain/reflect LLM calls.";
      };

      timeout = lib.mkOption {
        type = types.ints.positive;
        default = 120;
        description = "Timeout in seconds for Hindsight LLM calls through the external proxy.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.llama.enable;
        message = "services.hindsightMemory currently keeps local llama.cpp enabled for embeddings; set services.hindsightMemory.llama.enable = true or teach hindsight-embed.nix about an external embeddings provider.";
      }
      {
        assertion = lib.hasPrefix "http://" cfg.llm.baseUrl || lib.hasPrefix "https://" cfg.llm.baseUrl;
        message = "services.hindsightMemory.llm.baseUrl must include an http(s) scheme.";
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

      restartTriggers = [
        serviceEnvFile
        setupScript
        recoveryPreflightScript
        startScript
      ];

      serviceConfig = {
        Type = "simple";
        User = "hermes";
        StateDirectory = "hermes";
        Restart = "on-failure";
        RestartSec = "5s";
        EnvironmentFile = [ serviceEnvFile ];
        LoadCredential = [ "cliproxyapi-key:${config.sops.secrets.cliproxyapi-key.path}" ];
        ExecStartPre = [
          setupScript
          recoveryPreflightScript
        ];
        # Run hindsight-api directly in foreground (no --daemon flag).
        # systemd manages the lifecycle; daemon mode would fork away and break Type=simple.
        ExecStart = startScript;
      };
    };
  };
}

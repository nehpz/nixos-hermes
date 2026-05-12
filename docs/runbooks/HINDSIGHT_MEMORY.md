# Hindsight Memory Runbook

This runbook covers the host-local Hindsight memory substrate for `nixos-hermes`.

## Scope

The current deployment is a pragmatic local-memory substrate for Hermes:

- `llama-server.service` serves a local Gemma GGUF with llama.cpp on `127.0.0.1:8080`.
- `postgresql.service` provides the Hindsight database and `pgvector` extension.
- `hindsight-postgres-init.service` ensures `CREATE EXTENSION IF NOT EXISTS vector` runs for the `hermes` database.
- `hindsight-embed.service` runs `hindsight-api` on `127.0.0.1:8888`.
- `hermes-agent.service` uses the Hermes `hindsight` memory provider in `local_external` mode against that loopback API.

This is promoted from spike to host infrastructure for the personal assistant host, but it remains intentionally host-local. It is not a general reusable Den workload yet.

## Owning files

- `hosts/hermes/hindsight-memory.nix` — host-local enablement and Hermes provider wiring.
- `hosts/hermes/llama-server.nix` — llama.cpp service options and unit.
- `hosts/hermes/hindsight-embed.nix` — PostgreSQL/Hindsight API service and writable venv setup.
- `modules/packages.nix` — `opusCtypesShim`, including the Hindsight writable venv `sitecustomize.py` path hook.
- `flake.nix` — `checks.x86_64-linux.hindsight-service-config` regression check.

## Model file placement

The default model path is declared in `services.hindsightMemory.llama.modelPath` and currently points at:

```text
/var/lib/hermes/models/google_gemma-4-E2B-it-Q6_K_L.gguf
```

The model file is deliberately host state, not committed to the public repo. If it is missing, `llama-server-precheck` fails before `llama-server` starts and prints the expected path plus the option to override.

Check the file:

```bash
stat /var/lib/hermes/models/google_gemma-4-E2B-it-Q6_K_L.gguf
```

## Service graph

Expected relationships:

```text
postgresql.service
  └─ hindsight-postgres-init.service
       └─ hindsight-embed.service
            └─ hermes-agent.service

llama-server.service
  └─ hindsight-embed.service
```

`hermes-agent.service` is ordered after and requires `hindsight-embed.service` while `services.hindsightMemory.enable = true`, because Hindsight is the configured memory provider. Disabling the substrate removes that provider wiring and removes the managed provider config file during activation.

## Configuration generated at activation

The Hermes Hindsight provider reads `$HERMES_HOME/hindsight/config.json` before environment variables. The host therefore refreshes this file on every activation:

```json
{
  "mode": "local_external",
  "api_url": "http://127.0.0.1:8888",
  "bank_id": "hermes",
  "budget": "mid"
}
```

The service also exports matching non-secret environment variables as a belt-and-suspenders fallback:

- `HINDSIGHT_MODE=local_external`
- `HINDSIGHT_API_URL=http://127.0.0.1:8888`
- `HINDSIGHT_BANK_ID=hermes`
- `HINDSIGHT_BUDGET=mid`

No `HINDSIGHT_API_KEY` is required because the API is bound to loopback.

## Health checks

After a rebuild or switch:

```bash
systemctl show hermes-agent.service hindsight-embed.service llama-server.service postgresql.service hindsight-postgres-init.service \
  -p Id -p ActiveState -p SubState -p MainPID -p NRestarts -p ExecMainStatus -p ExecMainStartTimestamp --no-pager

systemctl --failed --no-pager

curl -fsS http://127.0.0.1:8080/health
curl -fsS http://127.0.0.1:8080/v1/models
curl -fsS http://127.0.0.1:8888/health

ss -ltnp | grep -E '(:8080|:8888)'
```

Expected:

- `hermes-agent`, `hindsight-embed`, `llama-server`, and `postgresql` are active/running.
- `hindsight-postgres-init` is inactive/dead with `ExecMainStatus=0` after completing its oneshot.
- llama health returns `{"status":"ok"}`.
- Hindsight health returns `{"status":"healthy","database":"connected"}`.

## Hermes provider smoke

Before activating a new config, use a temp `HERMES_HOME` to prove the provider config shape:

```bash
tmp=$(mktemp -d)
mkdir -p "$tmp/hindsight"
printf '%s' '{"mode":"local_external","api_url":"http://127.0.0.1:8888","bank_id":"hermes","budget":"mid"}' \
  > "$tmp/hindsight/config.json"

pid=$(systemctl show hermes-agent.service -p MainPID --value)
py=$(tr '\0' '\n' < /proc/$pid/environ | sed -n 's/^HERMES_PYTHON=//p')
pp=$(tr '\0' '\n' < /proc/$pid/environ | sed -n 's/^PYTHONPATH=//p')

env -i HOME=/var/lib/hermes HERMES_HOME="$tmp" PYTHONPATH="$pp" "$py" - <<'PY'
from plugins.memory.hindsight import HindsightMemoryProvider
p = HindsightMemoryProvider()
print('available', p.is_available())
p.initialize('hindsight-provider-smoke')
print('mode', p._mode)
print('api_url', p._api_url)
print('bank', p._bank_id)
PY

rm -rf "$tmp"
```

Expected:

```text
available True
mode local_external
api_url http://127.0.0.1:8888
bank hermes
```

For a full behavioral smoke after activation, start a fresh Hermes session and ask it to store a unique fact, then retrieve that fact in a second fresh session. The important part is cross-session retrieval through the Hindsight provider, not merely the built-in `MEMORY.md` file.

## Failure modes

### Model file missing

Symptom:

- `llama-server.service` fails before starting.
- `hindsight-embed.service` cannot start because it requires llama.
- `hermes-agent.service` will fail if it requires Hindsight as the configured provider.

Fix:

```bash
stat /var/lib/hermes/models/google_gemma-4-E2B-it-Q6_K_L.gguf
# restore the model file or override services.hindsightMemory.llama.modelPath
```

### Stale interactive Hindsight config

Symptom:

- Provider initializes as `local_embedded` or cloud despite Nix env vars.
- Logs mention local runtime import failures such as `No module named 'hindsight'`.

Cause:

- `$HERMES_HOME/hindsight/config.json` takes precedence over env vars.

Fix:

- Rebuild/switch with the declarative activation refresh, or inspect:

```bash
jq . /var/lib/hermes/.hermes/hindsight/config.json
```

### Writable venv Python mismatch

Symptom:

- Hermes cannot import `hindsight-client` even though `hindsight-embed` works.
- `sitecustomize.py` points at `/var/lib/hermes/.venv/lib/python3.13/site-packages` while Hermes runs Python 3.12.

Fix:

- `opusCtypesShim` derives the path from `sys.version_info`; rebuild to pick up the fixed generated shim.

### Hindsight API unhealthy

Symptom:

- `curl http://127.0.0.1:8888/health` does not return healthy/database connected.

Check:

```bash
systemctl show hindsight-embed.service postgresql.service hindsight-postgres-init.service \
  -p ActiveState -p SubState -p ExecMainStatus -p NRestarts --no-pager
```

Journal access may be restricted to non-journal users; use service state and HTTP health from the `hermes` account, or inspect journal from an admin shell.

## Rollback

Fast operational rollback is to revert/disable host-local Hindsight wiring and rebuild:

```nix
services.hindsightMemory.enable = false;
```

When disabled, the host config omits `services.hermes-agent.settings.memory.provider = "hindsight"`, omits the `hindsight-embed.service` requirement, and activation removes `$HERMES_HOME/hindsight/config.json` so stale provider config does not silently survive the rollback.

For a full revert, remove the import of `hosts/hermes/hindsight-memory.nix` and any Hindsight-specific service modules only after confirming no other active issue depends on them.

## Linear dogfood notes

What worked well:

- Project-scoped issues kept the spike from becoming a pile of ad hoc chat TODOs.
- Small Linear IDs (`ONE-20` through `ONE-37`) mapped cleanly to compact GitButler branches.
- Evidence comments after each PR made the host/rebuild state auditable.
- Review comments became follow-up tech-debt issues instead of derailing the current PR.

What was annoying:

- The Linear CLI state names differ from muscle memory; this team currently uses `Backlog`, `Review`, `Done`, and `Canceled`, not `In Progress`.
- CLI JSON shapes differ between `issues get` and `issues list`, so scripts must probe shape before assuming fields.
- Project closure still needs manual judgment: a project can have canceled or review issues that are effectively closed, but the API does not make that nuance obvious.

Template changes worth keeping:

- Include explicit validation commands in every implementation issue.
- Include a rollback criterion whenever a host-level service becomes part of the boot graph.
- Add a "review fallout" habit: if a bot review raises non-blocking but real tech debt, create a follow-up issue immediately and keep the original PR focused.

## Promotion decision

Promote this from spike to host-local infrastructure, with one caveat: it is not yet a generalized Den/Homelab workload pattern. The current implementation is acceptable for `nixos-hermes` because it is loopback-only, has explicit service health checks, has a rollback path, and is covered by the flake config check. Generalizing it should be a separate design pass, not a cleanup hidden inside this project.

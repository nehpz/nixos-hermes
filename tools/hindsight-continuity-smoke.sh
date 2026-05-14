#!/usr/bin/env bash
# Prove that the live Hermes/Hindsight wiring is useful, not merely running.
# Checks: service health -> Hermes runtime import path -> retain -> extraction/stats -> recall.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: tools/hindsight-continuity-smoke.sh [--bank BANK] [--api-url URL] [--timeout SECONDS]

Runs a live Hindsight continuity smoke check without printing credentials.
It uses the same Python interpreter and PYTHONPATH exported to hermes-agent.service
when that service is running, so import failures match the agent-facing tool path.

Environment overrides:
  HINDSIGHT_BANK_ID       bank to use (default: hermes)
  HINDSIGHT_API_URL       API URL (default: http://127.0.0.1:8888)
  HINDSIGHT_SMOKE_TIMEOUT max seconds for retain/recall (default: 180)
USAGE
}

bank="${HINDSIGHT_BANK_ID:-hermes}"
api_url="${HINDSIGHT_API_URL:-http://127.0.0.1:8888}"
timeout_seconds="${HINDSIGHT_SMOKE_TIMEOUT:-180}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bank)
      bank="$2"
      shift 2
      ;;
    --api-url)
      api_url="$2"
      shift 2
      ;;
    --timeout)
      timeout_seconds="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

export HINDSIGHT_SMOKE_BANK="$bank"
export HINDSIGHT_SMOKE_API_URL="$api_url"
export HINDSIGHT_SMOKE_TIMEOUT="$timeout_seconds"

python_bin="${HERMES_PYTHON:-}"
pythonpath="${PYTHONPATH:-}"
service_pid=""

if command -v systemctl >/dev/null 2>&1; then
  service_pid="$(systemctl show hermes-agent.service -p MainPID --value 2>/dev/null || true)"
fi

if [[ -n "$service_pid" && "$service_pid" != "0" && -r "/proc/$service_pid/environ" ]]; then
  while IFS= read -r entry; do
    case "$entry" in
      HERMES_PYTHON=*) python_bin="${entry#HERMES_PYTHON=}" ;;
      PYTHONPATH=*) pythonpath="${entry#PYTHONPATH=}" ;;
    esac
  done < <(tr '\0' '\n' < "/proc/$service_pid/environ")
fi

if [[ -z "$python_bin" ]]; then
  python_bin="$(command -v python3 || command -v python)"
fi

if [[ -n "$pythonpath" ]]; then
  export PYTHONPATH="$pythonpath"
fi

"$python_bin" - <<'PY'
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

api_url = os.environ["HINDSIGHT_SMOKE_API_URL"].rstrip("/")
bank = os.environ["HINDSIGHT_SMOKE_BANK"]
timeout = int(os.environ["HINDSIGHT_SMOKE_TIMEOUT"])


def request(method, path, payload=None):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{api_url}{path}",
        data=data,
        method=method,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=min(timeout, 60)) as resp:
            body = resp.read().decode("utf-8")
            try:
                return json.loads(body) if body else {}
            except json.JSONDecodeError as exc:
                raise SystemExit(f"FAIL: Invalid JSON response from {path}: {body[:200]}") from exc
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"FAIL: HTTP {exc.code} from {path}: {body[:1000]}") from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"FAIL: Connection error to {api_url}{path}: {exc.reason}") from exc


try:
    import hindsight_client  # noqa: F401
except Exception as exc:  # pragma: no cover - shell smoke output is the assertion
    raise SystemExit(f"FAIL: Hermes runtime cannot import hindsight_client: {exc}") from exc

health = request("GET", "/health")
if health.get("status") != "healthy" or health.get("database") != "connected":
    raise SystemExit(f"FAIL: unhealthy Hindsight API: {health}")

stats_before = request("GET", f"/v1/default/banks/{bank}/stats")

stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
marker = f"Hermes continuity smoke marker {stamp}"
query = f"What is the Hermes continuity smoke marker {stamp}?"
document_id = f"hindsight-continuity-smoke-{stamp}"
content = (
    f"{marker} proves Hindsight retain, fact extraction, and recall work through "
    "the live Hermes continuity smoke check."
)

retain = request(
    "POST",
    f"/v1/default/banks/{bank}/memories",
    {
        "async": False,
        "items": [
            {
                "content": content,
                "context": "hindsight-continuity-smoke",
                "document_id": document_id,
                "tags": ["hindsight-smoke", "continuity"],
                "metadata": {"source": "tools/hindsight-continuity-smoke.sh"},
            }
        ],
    },
)
if not retain.get("success"):
    raise SystemExit(f"FAIL: retain did not report success: {retain}")

last_recall = None
deadline = time.time() + timeout
while time.time() < deadline:
    last_recall = request(
        "POST",
        f"/v1/default/banks/{bank}/memories/recall",
        {
            "query": query,
            "budget": "mid",
            "max_tokens": 1024,
            "tags": ["hindsight-smoke"],
            "tags_match": "any_strict",
        },
    )
    results = last_recall.get("results") or []
    if any(
        marker in (result.get("text") or "") or result.get("document_id") == document_id
        for result in results
    ):
        break
    time.sleep(5)
else:
    raise SystemExit(
        "FAIL: recall did not return the retained marker before timeout; "
        f"last_recall={json.dumps(last_recall, sort_keys=True)[:2000]}"
    )

stats_after = request("GET", f"/v1/default/banks/{bank}/stats")

print("Hindsight continuity smoke: PASS")
print(f"- api_url: {api_url}")
print(f"- bank: {bank}")
print(f"- python: {sys.executable}")
print("- import: hindsight_client")
print(f"- health: {health['status']} / database={health['database']}")
print(f"- retained_marker: {marker}")
print(f"- retained_document_id: {document_id}")
print(f"- recall_results: {len(last_recall.get('results') or [])}")
print(f"- stats_before: {json.dumps(stats_before, sort_keys=True)[:500]}")
print(f"- stats_after: {json.dumps(stats_after, sort_keys=True)[:500]}")
PY

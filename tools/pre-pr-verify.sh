#!/usr/bin/env bash
# Run the mechanical pre-PR verification ladder for nixos-hermes.
# Default path is intentionally non-mutating and does not require root.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: tools/pre-pr-verify.sh [--quick] [--full] [--skip-dry-build]

Runs the local pre-PR gates that should catch mechanical Nix errors before review.

Modes:
  default          flake eval/check + host dry-build + generated-config checks
  --quick          flake eval/check + generated-config checks, skip dry-build
  --full           default + VM activation tests
  --skip-dry-build explicitly skip dry-build and record why via SKIP_REASON

Environment:
  CHECK_SYSTEM     flake system to use for system-specific checks (default: current system)
  SKIP_REASON      reason printed when a heavier gate is intentionally skipped

The script prints a compact evidence block suitable for Linear/PR comments.
USAGE
}

mode="default"
skip_dry_build=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick)
      mode="quick"
      skip_dry_build=true
      ;;
    --full)
      mode="full"
      ;;
    --skip-dry-build)
      skip_dry_build=true
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
  shift
done

if ! root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  root="$(pwd)"
fi
cd "$root"

run() {
  local name="$1"
  shift
  echo "==> $name"
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
  "$@"
  echo "ok: $name"
  echo
}

skip() {
  local name="$1"
  local reason="${SKIP_REASON:-not required for this change or intentionally deferred}"
  echo "skip: $name — $reason"
}

check_system="${CHECK_SYSTEM:-$(nix eval --impure --raw --expr builtins.currentSystem)}"
start_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
head_sha="$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
branch="$(git branch --show-current 2>/dev/null || echo unknown)"

run "flake eval/check" nix flake check --no-build --no-eval-cache
run "generated Hindsight service config invariants" nix build ".#checks.${check_system}.hindsight-service-config" --no-link -L

if [[ "$skip_dry_build" == true ]]; then
  skip "nixos-rebuild dry-build"
else
  run "nixos-rebuild dry-build" nixos-rebuild dry-build --flake .#nixos-hermes -L
fi

if [[ "$mode" == "full" ]]; then
  run "activation VM test: github auth provisioning" nix build ".#checks.${check_system}.activation-github-auth" --no-link -L
else
  skip "activation VM tests"
fi

cat <<EVIDENCE
Pre-PR verification evidence
- branch: ${branch}
- head: ${head_sha}
- started_utc: ${start_utc}
- mode: ${mode}
- check_system: ${check_system}
- flake eval/check: PASS
- generated service config invariants: PASS
- dry-build: $([[ "$skip_dry_build" == true ]] && echo "SKIPPED (${SKIP_REASON:-not required for this change or intentionally deferred})" || echo PASS)
- activation VM tests: $([[ "$mode" == "full" ]] && echo PASS || echo "SKIPPED (${SKIP_REASON:-not required for this change or intentionally deferred})")
EVIDENCE

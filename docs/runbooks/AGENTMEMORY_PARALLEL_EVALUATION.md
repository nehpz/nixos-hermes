# Agent Memory parallel evaluation

Agent Memory is installed on `nixos-hermes` as a parallel observer beside Hindsight. The first milestone is infrastructure only: Agent Memory may observe and answer explicit probes, but it must not inject context into routine Hermes turns until the evaluation gates say it is safe.

## Declarative service

The host imports `hosts/hermes/agentmemory.nix`, which defines and enables `services.agentmemory` by default for this host. Disable/rollback is one declarative change:

```nix
services.agentmemory.enable = false;
```

or remove the host import if the evaluation is fully abandoned.

The service runs as the `agentmemory` system user with persistent state under:

```text
/var/lib/agentmemory
```

Package pins:

- `@agentmemory/agentmemory`: `0.9.18`
- `iii-engine`: `0.11.2`

The Nix package uses the npm release tarball plus a fixed-output `node_modules` derivation. This intentionally avoids `npx -y`, global npm installs, or network-at-runtime package resolution in the systemd path.

## Listener contract

Expected local surfaces:

| Surface | Bind / URL |
| --- | --- |
| REST API | `http://127.0.0.1:3111/agentmemory/*` |
| Streams | `ws://127.0.0.1:3112` |
| Viewer | `http://127.0.0.1:3113` |
| iii bridge | `ws://127.0.0.1:49134` |

Upstream Agent Memory and the bundled `iii-config.yaml` bind REST/streams/viewer to loopback by default. The NixOS service also sets explicit loopback URLs and ports. Do not expose these listeners publicly during the shadow evaluation.

## Conservative flags

The service starts with influence-changing and expensive features off:

```env
AGENTMEMORY_ALLOW_AGENT_SDK=false
AGENTMEMORY_AUTO_COMPRESS=false
GRAPH_EXTRACTION_ENABLED=false
CONSOLIDATION_ENABLED=false
AGENTMEMORY_INJECT_CONTEXT=false
AGENTMEMORY_TOOLS=core
```

Hindsight remains the Hermes memory provider during this milestone.

## Evaluation gates

Promotion is gated by evidence, not by the service merely staying up:

| Gate | Criteria | Flags that may change after pass |
| --- | --- | --- |
| M1: declarative observer | Build/dry-build pass, loopback-only listeners, no runtime package install, service health OK, marker save/search survives restart, Hindsight continuity smoke still passes. | None; keep observer-only mode. |
| M2: automatic capture proof | A fixed session set produces Agent Memory records without manual API calls, captured content is redacted enough for this host, and capture does not alter Hermes prompts/tool routing. | Consider `AGENTMEMORY_ALLOW_AGENT_SDK=true` only if the SDK path is required for capture and remains non-influential. |
| M3: quality/noise bake-off | The comparison query set shows useful recall with acceptable false positives/duplicates versus Hindsight, including explicit misses and bad recalls. | Consider `GRAPH_EXTRACTION_ENABLED=true` or `CONSOLIDATION_ENABLED=true` one at a time for a measured retest. |
| M4: controlled influence trial | Human-approved narrow profile/session, fixed rollback point, prompt diff captured, no private/irrelevant memory injection, and Hindsight remains available as fallback. | Only then consider `AGENTMEMORY_INJECT_CONTEXT=true` for that controlled scope. |

Fail any ripcord below and stop promotion; do not relax another flag to compensate for a failed gate.

## Mechanical validation

Run the config invariant check after edits:

```bash
nix build .#checks.x86_64-linux.agentmemory-service-config --no-link -L
```

For normal pre-PR validation:

```bash
tools/pre-pr-verify.sh
```

For changes that affect activation/deployment mechanics, use the heavier VM switch smoke from `AGENTS.md`.

## Runtime smoke

After an authorized host switch/restart, prove runtime separately from build proof:

```bash
systemctl is-active agentmemory.service
ss -ltnp | grep -E ':(3111|3112|3113|49134)\b'
curl -fsS http://127.0.0.1:3111/agentmemory/health
```

Then save/search a marker and restart the service to prove persistence. Keep the exact API payloads/output in the Linear evidence comment for ONE-61. Do not call service health alone sufficient; ONE-61 requires health, listener binding, marker save/search, restart persistence, and Hindsight non-regression evidence.

## Ripcords

Disable Agent Memory and stop promotion if any of these occur:

- any listener binds publicly;
- the service uses runtime package installation;
- unredacted secrets/private infrastructure are captured;
- Agent Memory blocks Hermes startup, gateway startup, or MCP discovery;
- rollback cannot be represented as declarative configuration.

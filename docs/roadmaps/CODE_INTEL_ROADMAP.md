# Code Intelligence Roadmap

This document captures the durable plan for evolving the `code_intel` Hermes plugin after the Python-first MVP. It is intentionally written so another agent can resume the work later. Project-management migration to Linear is intentionally out of scope here; when that system exists, Linear issues can reference this roadmap rather than duplicating it.

## Stable baseline

Current baseline: **Python-first explicit toolset MVP**.

The baseline is stable when all of these are true:

- `services.hermes-agent.extraPlugins` includes the pinned `hermes-code-intel-plugin` directory plugin.
- `services.hermes-agent.settings.plugins.enabled` includes `code_intel`.
- Python package deps are scoped to the Hermes runtime interpreter (`python312Packages` for Hermes 0.12.0 on this host), not blindly to `pkgs.python3Packages`.
- Runtime packages include:
  - `pkgs.ast-grep`
  - `pkgs.pyrefly`
  - `pkgs.rust-analyzer`
- Pyrefly replaces Pyright for the Python LSP path.
- Upstream broad steering/default behavior is patched out:
  - no `pre_llm_call` auto-context hook
  - no `_HERMES_CORE_TOOLS` mutation
  - no builtin tool schema rewriting
  - no forced delegate `DEFAULT_TOOLSETS.append`
  - no subagent prompt/constructor monkey-patching
- Live-generation validation passes through `hermes chat --toolsets code_intel`, not only direct Python imports.

Validated live signals from the baseline:

- `hermes plugins list` shows `code_intel enabled`.
- `code_symbols`, `code_capsule`, `code_search`, and `code_workspace_summary` return compact useful results.
- `code_definition` and `code_references` use `method: lsp` with `lsp_server: pyrefly`.
- `code_diagnostics` returns zero diagnostics without failure. The plugin may label a zero-diagnostic response as `ast_heuristic` after LSP returns no items; treat that as plugin fallback labeling, not a Pyrefly startup failure.
- No lingering `pyrefly`, Pyright, `typescript-language-server`, `gopls`, or `rust-analyzer` processes remain after one-shot CLI runs.
- Cache under `$HERMES_HOME/plugins/code_intel/.cache/` stays small.
- Gateway logs show no `code_intel` errors.

## MVP acceptance standard

Do **not** count "it builds" as success. Do **not** count "works, sort of" as success.

A language/plugin expansion is acceptable only after proving:

1. Nix builds the full toplevel closure.
2. The live generation exposes the intended plugin/toolset/binary in the systemd service path.
3. The explicit `code_intel` toolset works through `hermes chat`, not just an isolated Python import.
4. At least one AST/symbol tool and one LSP navigation tool work on real code.
5. Failure modes are boring: no import explosions, no leaked LSP processes, no scary logs, no large cache growth.
6. The change is reversible as a narrow commit/PR.

## Lessons learned

### Match Hermes' Python runtime, not nixpkgs' default Python

Hermes 0.12.0 runs a sealed Python 3.12 environment on this host while pinned nixpkgs defaults to Python 3.13. Plugin Python deps must currently come from `pkgs.python312Packages`. Using `pkgs.python3Packages` would build for the wrong interpreter.

Directly invoking `$HERMES_PYTHON` is not always enough for tests: service `extraPythonPackages` may not appear unless the wrapper/service environment is used. For isolated probes, explicitly add the built plugin path plus each dependency site-packages path to `PYTHONPATH`, or prefer live `hermes chat --toolsets code_intel` after switching.

### Avoid duplicate sealed-venv deps

Hermes' sealed venv rejects package collisions. If a dependency is already present in Hermes' sealed environment, do not add another copy through `extraPythonPackages`. `pyyaml` was one such collision during this work.

### Prefer Pyrefly over Pyright for this MVP

Pyright functionally passed basic smoke tests but inferred Python 3.13 while Hermes ran Python 3.12. That is exactly the kind of subtle mismatch that creates plausible lies later.

Pyrefly 0.60.0 initialized cleanly as `pyrefly-lsp 0.60.0`, returned LSP definitions/references, responded to diagnostics, and exited cleanly. Use Pyrefly as the Python LSP unless a future test gives a concrete reason not to.

`ty` is worth watching. It is packaged, but in this pin it is still `0.0.1-alpha.32`; treat it as future-track, not the default.

### Patch upstream broad hooks last

The upstream plugin tries to realize value by changing agent behavior globally. That is powerful, but too invasive for the baseline. Broad hooks are not "the rest of the plugin"; they are **automation of trust**.

Only re-enable them after explicit tool use has earned trust on several real coding tasks.

### Keep language additions narrow

Each language should land as its own branch/PR or at least its own clean commit:

1. Runtime binary addition.
2. AST grammar/package addition.
3. Plugin source patch to register extension/language/server.
4. Live `hermes chat` validation.
5. Docs/roadmap update.

Do not bundle TypeScript, Rust, Nix, Go, Java, and broad hooks together. That would recreate the exact mess the Python-first MVP avoided.

### Tree-sitter grammar packaging is the slow path

The plugin imports tree-sitter grammar Python packages eagerly. TypeScript, Go, and Java PyPI sdists expected `tree_sitter/parser.h`, while Nix's `tree-sitter` package exposes `include/tree_sitter/api.h`. For those languages, either fetch a compatible wheel, patch the include layout, or avoid the Python grammar path and lean on LSP/CLI tools first.

## Roadmap

### Phase 0 — Land Python-first MVP

Status: ready after live Pyrefly validation.

Deliverables:

- PR containing the Python-first explicit `code_intel` toolset.
- PR body documents:
  - Pyrefly over Pyright rationale.
  - Broad hooks intentionally deferred.
  - TypeScript/Rust/Nix/Go follow-ups.
  - Live validation commands/results.

### Phase 1 — TypeScript / TSX

Why next: highest broad non-Python value; Hermes TUI/WebUI and many agent-adjacent tools are TypeScript-heavy. `rzp-labs/oh-my-pi` is a good future fixture because it combines heavy TS with Rust-built native tooling and is maintained in the same org.

Likely runtime package:

- `pkgs.typescript-language-server`

Work items:

- Solve `tree-sitter-typescript` packaging or find a compatible wheel/source approach.
- Restore TypeScript/TSX eager imports and parser registrations in `code_intel.py`.
- Keep JavaScript support intact; avoid broad sed patterns that delete `tree_sitter_javascript` when removing `tree_sitter_java`.
- Validate on real `.ts` and `.tsx` files. Candidate fixture: <https://github.com/rzp-labs/oh-my-pi>.
- Check for lingering `typescript-language-server` / `tsserver` processes.

Acceptance: one TS project/file shows AST symbols and LSP definition/reference through live `hermes chat --toolsets code_intel`.

### Phase 2 — Rust

Why: the MVP already includes `tree-sitter-rust` and `rust-analyzer`, but we have not proven Rust live yet.

Work items:

- Validate `.rs` extension detection and Rust symbol queries.
- Validate `rust-analyzer` LSP registration. Upstream `lsp_bridge.py` does not currently list Rust in `_LANGUAGE_SERVERS`, so add:
  - command: `rust-analyzer`
  - args: likely `[]`
  - language_id: `rust`
- Validate on a real Cargo project if available, or a small temporary Cargo fixture.
- Check process cleanup.

Acceptance: `code_symbols`, `code_definition`, and `code_references` work on Rust code through live Hermes chat.

### Phase 3 — Nix

Short answer: **not compatible out of the box, but absolutely worth adding.**

Current facts from this repo's pinned package set:

- `pkgs.nil`: available
- `pkgs.nixd`: available
- `pkgs.statix`: available
- `pkgs.deadnix`: available
- `pkgs.alejandra`: available
- `pkgs.python312Packages.tree-sitter-nix`: not available
- `ast-grep` itself supports `-l nix` and can parse `.nix` files.

Implication:

- LSP support should be feasible first via `nil` or `nixd`.
- AST search may be feasible through the `ast-grep` CLI even without Python `tree-sitter-nix` bindings.
- Full `code_symbols` support will require custom work because upstream `code_intel.py` does not map `.nix`, has no Nix symbol queries, and lacks a Python tree-sitter Nix grammar in the pinned package set.

Recommended Nix path:

1. Add `.nix -> nix` to `_EXT_TO_LANG`.
2. Add `nix` to `_AST_GRASP_LANGS` if ast-grep-backed search is used.
3. Add Nix LSP server config in `lsp_bridge.py`, starting with `nil`:
   - command: `nil`
   - args: likely `[]`
   - language_id: `nix`
4. Validate `code_definition`, `code_references`, and `code_diagnostics` on this repo's Nix modules.
5. For symbol extraction, start with a practical Nix-specific fallback rather than blocking on Python tree-sitter bindings:
   - extract top-level attr assignments such as `services.hermes-agent`, `systemd.services.*`, `environment.systemPackages`, `let` bindings, and package definitions;
   - or shell out to `ast-grep -l nix --json` with curated patterns.
6. Only later chase proper Python `tree-sitter-nix` bindings if the fallback is insufficient.

Nix has outsized value for this host. There is much less model prior/training data for Nix than for Python/TypeScript/Go, and most high-impact host changes here are NixOS module edits. Good Nix code-intel would pay for itself quickly.

Acceptance for first Nix PR:

- `code_definition` or `code_diagnostics` works via `nil`/`nixd` on `modules/hermes-plugins.nix`.
- `code_search` can find Nix attr patterns using ast-grep or a documented fallback.
- A Nix-specific `code_symbols` fallback returns useful module-level symbols/attrs.
- No broad hooks are enabled.

### Phase 4 — Go

Why: useful for infra/server tooling eventually, but lower immediate value than Nix on this host because there is no current Go-heavy target repo.

Likely runtime package:

- `pkgs.gopls`

Work items:

- Solve or bypass `tree-sitter-go` Python grammar packaging.
- Add Go to `_LANGUAGE_SERVERS`:
  - command: `gopls`
  - args: probably `[]`
  - language_id: `go`
- Validate in a real `go.mod` workspace or a minimal temporary module.
- Check process cleanup.

Acceptance: `code_definition` and `code_references` use `gopls`; AST symbols either work or the PR explicitly documents LSP-only Go support.

### Phase 5 — Broad hooks, in layers

Only after multiple real tasks show explicit `code_intel` reduces context bloat and wrong-file edits.

Suggested order:

1. Builtin tool description hints only.
2. Subagents can opt into `code_intel` as an available toolset.
3. `pre_llm_call` auto-context hook with hard caps and clear trigger rules.
4. Prompt steering injection.
5. Default subagent toolset inclusion.

Acceptance before each layer:

- The previous layer improved real coding sessions.
- No non-code sessions got polluted.
- Tool/schema overhead stayed reasonable.
- Reverting the layer is a clean commit.

## Validation command template

Use this for every language PR, adapted to a real file of that language:

```bash
nix build .#nixosConfigurations.nixos-hermes.config.system.build.toplevel -L --no-link
nixos-rebuild dry-build --flake .#nixos-hermes -L --show-trace
nix flake check --no-build --no-eval-cache
nix build .#checks.x86_64-linux.pre-commit-check -L

# after switching to the generation:
systemctl is-active hermes-agent.service
hermes plugins list | grep -A4 code_intel
hermes chat -q 'Use code_symbols on /path/to/file and answer only with symbol names.' --toolsets code_intel -Q
hermes chat -q 'Use code_definition on /path/to/file line N character C. Answer only with method, lsp_server, and definition_count.' --toolsets code_intel -Q
hermes chat -q 'Use code_references on /path/to/file line N character C. Answer only with method, lsp_server, and reference_count.' --toolsets code_intel -Q
hermes chat -q 'Use code_diagnostics on /path/to/file. Answer only with diagnostic count, method, and LSP server if present.' --toolsets code_intel -Q
ps -eo pid,ppid,stat,comm,args | grep -E 'pyrefly|typescript-language-server|gopls|rust-analyzer|nil|nixd' | grep -v grep || true
du -sh /var/lib/hermes/.hermes/plugins/code_intel 2>/dev/null || true
```

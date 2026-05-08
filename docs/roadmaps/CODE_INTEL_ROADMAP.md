# Code Intelligence Roadmap

This document captures the durable plan for evolving the `code_intel` Hermes plugin after the upstream-aligned baseline. It is intentionally scoped to code intelligence; Linear/project-management migration is a separate workstream and can reference this roadmap later.

## Current baseline

The clean baseline should answer one question: can we declaratively package upstream `hermes-code-intel-plugin` for this NixOS Hermes host and run it on a reversible generation?

Baseline shape:

- Package upstream as a directory plugin with `services.hermes-agent.extraPlugins`.
- Satisfy upstream's eager tree-sitter grammar imports instead of pruning source.
- Patch only Python LSP selection from Pyright to Pyrefly.
- Let upstream hooks/toolset injection run as upstream designed.
- Validate live; rollback the generation if the hooks are noisy or slow.

The only intentional source behavior change is Pyrefly:

- Pyright inferred Python 3.13 in this environment.
- Hermes 0.12.0 runs a sealed Python 3.12 runtime.
- Pyrefly 0.60.0 was validated live for definition/reference lookups and clean process teardown.

## Lessons learned

1. **Integration first, surgery last.** Third-party plugin MVPs are packaging + runtime proof, not local redesign.
2. **Patch observed failure boundaries only.** Missing grammars are a dependency problem if wheels exist; do not delete language support just because the language is not validated yet.
3. **Build success is not enough.** Runtime `hermes chat` tests and log/process checks are required.
4. **Match Hermes' Python runtime.** This host's Hermes 0.12.0 wrapper uses Python 3.12 while pinned nixpkgs defaults to Python 3.13.
5. **Broad hooks are a product decision.** For this generation, we intentionally accept upstream hooks because rollback is easy and the alternative local fork is higher maintenance risk.
6. **Keep future languages narrow.** A language is not “supported” merely because its grammar dependency is present to satisfy upstream eager imports.

## Validation ladder

For every code-intel change:

```bash
nix build .#nixosConfigurations.nixos-hermes.config.system.build.toplevel -L --no-link
nix flake check --no-build --no-eval-cache
nixos-rebuild dry-build --flake .#nixos-hermes -L --show-trace
nix build .#checks.x86_64-linux.pre-commit-check -L
```

After switch, run live checks:

```bash
systemctl is-active hermes-agent.service
hermes plugins list | grep -A4 code_intel
hermes chat -q 'Use code_symbols on /path/to/file.py and answer only with symbol names.' --toolsets code_intel -Q
hermes chat -q 'Use code_definition on /path/to/file.py line N character C. Answer with method, lsp_server, and definition_count.' --toolsets code_intel -Q
hermes chat -q 'Use code_references on /path/to/file.py line N character C. Answer with method, lsp_server, and reference_count.' --toolsets code_intel -Q
ps -eo pid,ppid,stat,comm,args | grep -E 'pyrefly|pyright-langserver|typescript-language-server|tsserver|gopls|rust-analyzer' | grep -v grep || true
```

## Language roadmap

### Phase 0 — upstream-aligned baseline

Status: current PR target.

Package all eager grammar deps, but validate Python/Pyrefly first. The presence of TS/Go/Java grammar wheels means upstream initialization works; it does not mean those languages have earned support claims.

Acceptance:

- `code_intel` plugin loads in the switched generation.
- Python `code_symbols`, `code_definition`, and `code_references` work on real runtime code.
- Pyrefly appears in logs; Pyright does not.
- No language-server processes linger after one-shot sessions.
- Hook behavior is observed and considered acceptable or quickly rolled back.

### Phase 1 — TypeScript / TSX

Fixture: <https://github.com/rzp-labs/oh-my-pi>

Why next:

- Heavy TypeScript/TSX usage.
- Maintained by `rzp-labs`.
- Includes Rust-built native tooling, making it useful again for Rust later.

Known facts:

- `tree_sitter_typescript` wheel works on this x86_64 NixOS host.
- `typescript-language-server` is available in pinned nixpkgs.
- Prior spike on `/tmp/oh-my-pi/packages/stats/src/client/App.tsx` found symbols `Tab`, `App`, and `handleSync`, and LSP definition/references worked.

Acceptance:

- Live `hermes chat --toolsets code_intel` validates `code_symbols`, `code_definition`, `code_references`, and `code_diagnostics` on TSX.
- Logs show `typescript-language-server` startup and clean shutdown.
- Results use correct JSON keys: `definitions` and `references`, not generic `locations`.

### Phase 2 — Rust

Why:

- `tree-sitter-rust` is already packaged.
- `oh-my-pi` gives a realistic Rust-built tooling fixture.

Current gap:

- Upstream `lsp_bridge.py` does not define a Rust language-server entry, so `rust-analyzer` is not used until we add/validate that mapping.

Acceptance:

- AST symbols work on real `.rs` files.
- If LSP is added, `rust-analyzer` definition/references work and tear down cleanly.

### Phase 3 — Nix

Why:

- This host/repo is Nix-heavy.
- LLM priors for Nix are weaker than Python/TS/Go, so structured navigation has high leverage.

Known facts:

- `pkgs.nil`, `pkgs.nixd`, `pkgs.statix`, `pkgs.deadnix`, and `pkgs.alejandra` are available.
- `python312Packages.tree-sitter-nix` is absent.
- `ast-grep -l nix` can parse Nix files in this repo.

Likely path:

- Add `.nix -> nix` detection.
- Add `nil` or `nixd` LSP mapping.
- Use ast-grep/fallback symbol extraction before chasing Python tree-sitter bindings.

### Phase 4 — Go

Go moves after Nix because we do not currently have a strong Go-heavy target. Its grammar wheel is packageable, but support claims should wait for a real fixture and live validation.

### Phase 5 — Broad-hook refinement

The upstream baseline intentionally allows hooks to run. Later work should decide whether to keep them, tune them, make them configurable upstream, or carry a small disable/tuning patch.

Acceptance:

- Measured latency/noise impact.
- Evidence from normal coding sessions, not just synthetic one-shot calls.
- If we patch, one concern per patch and clear upstream-removal criteria.

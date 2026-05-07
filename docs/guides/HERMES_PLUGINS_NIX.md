# Hermes Plugins on NixOS

Hermes 0.12.0 can install plugins declaratively from the NixOS module. Use that path here; do not run `hermes plugins install` on the host and do not `pip install` into `/var/lib/hermes`.

## Plugin types

### Entry-point Python plugins

Use `services.hermes-agent.extraPythonPackages` for pip-style packages that expose the `hermes_agent.plugins` entry point group.

Example: `rtk-hermes` exposes:

```toml
[project.entry-points."hermes_agent.plugins"]
rtk-rewrite = "rtk_hermes"
```

Pattern:

```nix
let
  # Match the Python package set used by the Hermes Agent package. On this
  # Hermes 0.12.0 pin the service wrapper runs Python 3.12 even though the
  # pinned nixpkgs default `pkgs.python3` is newer, so do not blindly use
  # `pkgs.python3Packages` unless the Hermes package pin moves with it.
  pythonPackages = pkgs.python312Packages;

  myPlugin = pythonPackages.buildPythonPackage rec {
    pname = "my-hermes-plugin";
    version = "1.2.3";
    src = pkgs.fetchFromGitHub {
      owner = "owner";
      repo = "repo";
      rev = "v${version}";
      hash = "sha256-...";
    };
    pyproject = true;
    build-system = [ pythonPackages.setuptools ];
    pythonImportsCheck = [ "import_name" ];
  };
in
{
  services.hermes-agent = {
    extraPythonPackages = [ myPlugin ];
    settings.plugins.enabled = [ "entry-point-name" ];
  };
}
```

### Directory plugins

Use `services.hermes-agent.extraPlugins` for source-tree plugins with `plugin.yaml` and `__init__.py`.

Pattern:

```nix
let
  myDirectoryPlugin = pkgs.fetchFromGitHub {
    name = "my-directory-plugin";
    owner = "owner";
    repo = "repo";
    rev = "<commit-or-tag>";
    hash = "sha256-...";
  };
in
{
  services.hermes-agent = {
    extraPlugins = [ myDirectoryPlugin ];
    settings.plugins.enabled = [ "plugin.yaml-name" ];
  };
}
```

Directory plugins that import third-party Python modules also need those modules in `extraPythonPackages`. Plugins that shell out to external tools also need those binaries in `extraPackages`.

## Repeatable add/update workflow

1. Identify plugin shape:
   - `pyproject.toml` with `[project.entry-points."hermes_agent.plugins"]` → `extraPythonPackages`.
   - `plugin.yaml` + `__init__.py` → `extraPlugins`.
   - Both shapes or runtime imports → combine `extraPlugins`, `extraPythonPackages`, and `extraPackages`.
2. Pin by immutable tag or commit. Prefer releases for packaged plugins and commit SHAs for unreleased directory plugins.
3. Start with `pkgs.lib.fakeHash` for the source hash, build once, then replace it with the hash Nix reports.
4. Add the plugin name to `services.hermes-agent.settings.plugins.enabled`.
5. Add runtime binaries to `services.hermes-agent.extraPackages` when the plugin shells out. Example: `rtk-hermes` needs `pkgs.llm-agents.rtk` from the llm-agents overlay.
6. Validate:

   ```bash
   nix build .#nixosConfigurations.nixos-hermes.config.services.hermes-agent.package -L --no-link
   nixos-rebuild dry-build --flake .#nixos-hermes -L --show-trace
   nix build .#checks.x86_64-linux.pre-commit-check -L
   nix flake check --no-build --no-eval-cache
   ```

7. After deployment, restart/new-session Hermes and verify discovery from the service user's environment:

   ```bash
   sudo -u hermes --set-home hermes plugins list
   sudo -u hermes --set-home rtk --version
   ```

## Currently enabled

### `rtk-rewrite`

Source: <https://github.com/ogallotti/rtk-hermes>

Shape: entry-point Python plugin plus runtime binary.

Nix wiring:

- `extraPythonPackages`: `rtk-hermes`
- `extraPackages`: `rtk`
- `settings.plugins.enabled`: `rtk-rewrite`

Why it is a good first plugin: it is small, packaged, fail-open, and does not add tools or alter tool schemas. It intercepts the existing terminal tool through `pre_tool_call`, asks `rtk rewrite` for a lower-context equivalent, and lets RTK filter command output.

## Follow-up pilot: code intelligence plugin

Candidate: <https://github.com/rewasa/hermes-code-intel-plugin>

`code_intel` is deliberately landing as a **Python-first MVP** on a separate stacked branch from `rtk-rewrite`. It is strategically the right direction — AST/LSP-aware navigation should beat regex search and raw file reads for coding sessions — but it is materially riskier than `rtk-hermes`, so the pilot keeps variables tight:

- Directory plugin source is wired through `extraPlugins`.
- Python dependencies are limited to the grammars already available in the pinned Hermes Python package set: Python, JavaScript, and Rust.
- Runtime binaries are limited to `ast-grep`, `pyrefly`, and `rust-analyzer`. Pyrefly is preferred over Pyright for the MVP because Pyright's smoke tests worked but it inferred Python 3.13 while Hermes 0.12.0 runs on Python 3.12.
- TypeScript, Go, and Java grammar support are intentionally deferred; their PyPI sdists currently expect `tree_sitter/parser.h`, which the pinned Nix tree-sitter package does not expose.
- The upstream plugin's broad prompt/toolset steering is patched out for the MVP. It exposes the explicit `code_intel` toolset, but does not force itself into core toolsets, every subagent, builtin tool descriptions, or every coding prompt.

Acceptance test for the pilot:

1. Build the full NixOS toplevel closure.
2. Verify plugin registration exposes the `code_intel` toolset and `code_symbols` without mutating `_HERMES_CORE_TOOLS`.
3. Verify `code_symbols_tool()` on real Python code from the built Hermes/plugin runtime.
4. Only after that known-good Python path lands, add TypeScript grammar/LSP support in a separate follow-up commit.

That gives us a clean rollback boundary if its hooks or toolset injection are noisy.

Durable follow-up plan: see [`docs/roadmaps/CODE_INTEL_ROADMAP.md`](../roadmaps/CODE_INTEL_ROADMAP.md) for the language expansion roadmap, Linear migration notes, and lessons learned from the Pyrefly/Pyright spike.

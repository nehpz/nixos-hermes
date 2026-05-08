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

### `code_intel`

Source: <https://github.com/rewasa/hermes-code-intel-plugin>

Shape: directory plugin plus Python grammar dependencies and runtime binaries.

Nix wiring:

- `extraPlugins`: pinned upstream plugin source.
- `extraPythonPackages`: `ast-grep-py`, `tree-sitter`, and the tree-sitter grammar packages upstream imports eagerly.
- `extraPackages`: `ast-grep`, `pyrefly`, and `typescript-language-server` on the Hermes service PATH.
- `settings.plugins.enabled`: `code_intel`.

This deployment intentionally keeps upstream behavior intact. The plugin registers its toolset, hooks, tool-schema steering, and delegation integration as upstream designed. That is a broader runtime change than `rtk-rewrite`, but it is cleaner and more reversible than carrying a local fork-shaped patch. If the hooks are noisy, roll back the generation or disable `code_intel` in Nix.

The only source behavior change is Python LSP selection: Pyright is replaced with Pyrefly because Pyright inferred Python 3.13 in this environment while Hermes 0.12.0 runs Python 3.12. Pyrefly was validated live for definition/reference lookups and clean process teardown.

Durable follow-up plan: see [`docs/roadmaps/CODE_INTEL_ROADMAP.md`](../roadmaps/CODE_INTEL_ROADMAP.md).

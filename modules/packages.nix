{
  pkgs,
  lib,
  nixpkgs-llama,
  llm-agents,
  ...
}:

# Local package overrides — packages not yet available in the pinned nixpkgs channel.
# Also owns NixOS packaging workarounds that are packaging concerns, not service config.
let
  # nixpkgs patches CPython with no-ldconfig.patch — ctypes.util._findSoname_ldconfig
  # unconditionally returns None. LD_LIBRARY_PATH and ldconfig cache approaches are
  # both dead. Inject a sitecustomize.py via PYTHONPATH that patches find_library("opus")
  # to return the Nix store path directly before any user code runs.
  opusCtypesShim = pkgs.writeTextDir "sitecustomize.py" ''
    import ctypes.util as _cu
    import sys as _sys

    _OPUS_PATH = "${pkgs.libopus}/lib/libopus.so.0"
    _orig = _cu.find_library

    def find_library(name, *args, **kwargs):
        if name == "opus":
            return _OPUS_PATH
        return _orig(name, *args, **kwargs)

    _cu.find_library = find_library

    # Append the writable hindsight venv to sys.path so hindsight-client is importable.
    # Append (not prepend) so hermes-agent-env packages take precedence — this is required
    # because pip-installed numpy lacks the NixOS patchelf rpath and will fail to load
    # libstdc++.so.6 if it appears before the store copy.
    _hindsight_venv = "/var/lib/hermes/.venv/lib/python${pkgs.python3.pythonVersion}/site-packages"
    import os as _os
    if _os.path.isdir(_hindsight_venv) and _hindsight_venv not in _sys.path:
        _sys.path.append(_hindsight_venv)
  '';
in
{
  # Allow specific unfree packages needed by the system.
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "claude-code"
      "but"
    ];

  nixpkgs.overlays = [
    # llm-agents.nix provides claude-code, codex, omp, agent-browser, and many more.
    # Uses shared-nixpkgs overlay so packages build against our pkgs (not blueprint thunks).
    llm-agents.overlays.shared-nixpkgs
    (_final: prev: {
      # Exposed via overlay so consumers (hermes-agent.nix) can reference
      # pkgs.opusCtypesShim without packages.nix coupling to any service.
      inherit opusCtypesShim;
      # llama-cpp b6981 (pinned nixpkgs) predates Gemma 4 arch support (requires >= b8637).
      # Override with b8770 from nixpkgs-llama until FlakeHub NixOS/nixpkgs/0 catches up.
      llama-cpp = (nixpkgs-llama.legacyPackages.${pkgs.system}).llama-cpp;

      llm-agents = prev.llm-agents // {
        but = prev.llm-agents.but.overrideAttrs (
          oldAttrs:
          let
            patchButSource = ''
              ${pkgs.python3}/bin/python3 - <<'PY'
              import re
              from pathlib import Path

              cargo_toml = Path("crates/gitbutler-git/Cargo.toml")
              cargo_toml_text = cargo_toml.read_text()

              def normalize_file_id_dependency(match):
                  inline_table = match.group(1)
                  fields = dict(
                      re.findall(r'''([A-Za-z0-9_-]+)\s*=\s*["']([^"']+)["']''', inline_table)
                  )
                  if fields == {
                      "git": "https://github.com/notify-rs/notify",
                      "rev": "978fe719b066a8ce76b9a9d346546b1569eecfb6",
                      "version": "0.2.3",
                  }:
                      return 'file-id = "0.2.3"'
                  return match.group(0)

              cargo_toml_text, replacement_count = re.subn(
                  r'''file-id\s*=\s*\{([^}]+)\}''',
                  normalize_file_id_dependency,
                  cargo_toml_text,
                  count=1,
              )
              if replacement_count != 1 or "https://github.com/notify-rs/notify" in cargo_toml_text:
                  raise RuntimeError("failed to normalize file-id dependency in Cargo.toml")
              cargo_toml.write_text(cargo_toml_text)

              lock = Path("Cargo.lock")
              text = lock.read_text()
              blocks = text.split("[[package]]\n")
              registry_sources = {}
              package_sources = []
              for block in blocks[1:]:
                  fields = {}
                  for line in block.splitlines():
                      if line.startswith(('name = ', 'version = ', 'source = ')):
                          key, value = line.split(' = ', 1)
                          fields[key] = value.strip('"')
                  name = fields.get('name')
                  version = fields.get('version')
                  source = fields.get('source')
                  if name and version and source:
                      package_sources.append((name, version, source, block))
                      if source.startswith('registry+'):
                          registry_sources[(name, version)] = source

              git_sources_to_normalize = {
                  (name, version, source): registry_sources[(name, version)]
                  for name, version, source, _block in package_sources
                  if source.startswith('git+') and (name, version) in registry_sources
              }

              kept = [blocks[0]]
              for block in blocks[1:]:
                  fields = {}
                  for line in block.splitlines():
                      if line.startswith(('name = ', 'version = ', 'source = ')):
                          key, value = line.split(' = ', 1)
                          fields[key] = value.strip('"')
                  identity = (fields.get('name'), fields.get('version'), fields.get('source'))
                  if identity in git_sources_to_normalize:
                      continue
                  kept.append('[[package]]\n' + block)

              normalized_lock = "".join(kept)
              for (name, version, git_source), registry_source in git_sources_to_normalize.items():
                  normalized_lock = normalized_lock.replace(
                      f' "{name} {version} ({git_source.split("#", 1)[0]})",',
                      f' "{name} {version} ({registry_source})",',
                  )
              lock.write_text(normalized_lock)
              PY
            '';
            patchedSrc = pkgs.runCommand "gitbutler-${oldAttrs.version}-but-patched-source" { } ''
              cp -R ${oldAttrs.src} "$out"
              chmod -R u+w "$out"
              cd "$out"
              ${patchButSource}
            '';
          in
          {
            # GitButler's lockfile contains git-sourced crates that have the same
            # name/version as crates.io entries in the same workspace (`file-id`,
            # `gix-trace`). nixpkgs' fetch-cargo-vendor cannot vendor both
            # sources under one `<name>-<version>` directory, so normalize these
            # duplicate git entries to their crates.io source before vendoring
            # instead of removing the package from the system.
            src = patchedSrc;
            cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
              src = patchedSrc;
              name = "${oldAttrs.pname}-${oldAttrs.version}-vendor";
              hash = "sha256-cPcVD5HTvkxb1ylZr+XwPYER9kHLFOkGdqCkNitK8HM=";
            };
          }
        );
      };
    })
  ];
}

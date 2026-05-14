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

    _OPUS_PATH = "${pkgs.libopus}/lib/libopus.so.0"
    _orig = _cu.find_library

    def find_library(name, *args, **kwargs):
        if name == "opus":
            return _OPUS_PATH
        return _orig(name, *args, **kwargs)

    _cu.find_library = find_library
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

      linear-cli = prev.buildGoModule rec {
        pname = "linear-cli";
        version = "1.8.1";

        src = prev.fetchFromGitHub {
          owner = "joa23";
          repo = "linear-cli";
          rev = "v${version}";
          hash = "sha256-7Yk/UzbZ5P7awctHwFNVUMEgFN3fUATqHZZm9RdSLfE=";
        };

        vendorHash = "sha256-Ype8lW/3wbIbbFhPMwXEnm+9tEMPYMqPIxg8ykeK8v0=";

        subPackages = [ "cmd/linear" ];
        env.CGO_ENABLED = 0;
        ldflags = [ "-X github.com/joa23/linear-cli/internal/cli.Version=v${version}" ];
        preCheck = ''
          unset LINEAR_API_KEY
        '';

        meta = {
          description = "Token-efficient Linear CLI optimized for AI agent workflows";
          homepage = "https://github.com/joa23/linear-cli";
          license = lib.licenses.mit;
          mainProgram = "linear";
          platforms = lib.platforms.linux ++ lib.platforms.darwin;
        };
      };

      # llama-cpp b6981 (pinned nixpkgs) predates Gemma 4 arch support (requires >= b8637).
      # Override with b8770 from nixpkgs-llama until FlakeHub NixOS/nixpkgs/0 catches up.
      llama-cpp = (nixpkgs-llama.legacyPackages.${prev.stdenv.hostPlatform.system}).llama-cpp;

      llm-agents = prev.llm-agents // {
        but = prev.llm-agents.but.overrideAttrs (
          oldAttrs:
          let
            patchButSource = ''
              ${pkgs.python3}/bin/python3 - <<'PY'
              import tomllib
              from pathlib import Path

              cargo_toml = Path("crates/gitbutler-git/Cargo.toml")
              cargo_toml_text = cargo_toml.read_text()
              def find_file_id_dependencies(value):
                  if isinstance(value, dict):
                      if "file-id" in value:
                          yield value["file-id"]
                      for child in value.values():
                          yield from find_file_id_dependencies(child)

              file_id_dependencies = list(find_file_id_dependencies(tomllib.loads(cargo_toml_text)))
              if file_id_dependencies != [
                  {
                      "git": "https://github.com/notify-rs/notify",
                      "rev": "978fe719b066a8ce76b9a9d346546b1569eecfb6",
                      "version": "0.2.3",
                  }
              ]:
                  raise RuntimeError(f"unexpected file-id dependencies: {file_id_dependencies!r}")

              lines = cargo_toml_text.splitlines(keepends=True)
              replacement_count = 0
              for index, line in enumerate(lines):
                  if line.lstrip().startswith("file-id ="):
                      if replacement_count:
                          raise RuntimeError("found multiple file-id dependency lines")
                      indent = line[: len(line) - len(line.lstrip())]
                      newline = "\n" if line.endswith("\n") else ""
                      lines[index] = f'{indent}file-id = "0.2.3"{newline}'
                      replacement_count += 1

              cargo_toml_text = "".join(lines)
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

              lock.write_text("".join(kept))
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

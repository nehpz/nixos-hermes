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
    ];

  nixpkgs.overlays = [
    # llm-agents.nix provides claude-code, codex, omp, agent-browser, and many more.
    # Uses shared-nixpkgs overlay so packages build against our pkgs (not blueprint thunks).
    llm-agents.overlays.shared-nixpkgs
    (_final: _: {
      # Exposed via overlay so consumers (hermes-agent.nix) can reference
      # pkgs.opusCtypesShim without packages.nix coupling to any service.
      inherit opusCtypesShim;
      # llama-cpp b6981 (pinned nixpkgs) predates Gemma 4 arch support (requires >= b8637).
      # Override with b8770 from nixpkgs-llama until FlakeHub NixOS/nixpkgs/0 catches up.
      llama-cpp = (nixpkgs-llama.legacyPackages.${pkgs.system}).llama-cpp;
    })
  ];
}

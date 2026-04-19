{
  config,
  pkgs,
  lib,
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
  nixpkgs.overlays = [
    (final: _: {
      agent-browser = final.callPackage ../packages/agent-browser { };
      # Exposed via overlay so consumers (hermes-agent.nix) can reference
      # pkgs.opusCtypesShim without packages.nix coupling to any service.
      inherit opusCtypesShim;
    })
  ];
}

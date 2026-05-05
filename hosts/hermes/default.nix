{ lib, ... }:

{
  imports = [
    ./hardware.nix
    ./disk-config.nix
    ./sops.nix
    ./provision.nix
    ../../modules/system.nix
    ../../modules/packages.nix
    ../../modules/hermes-agent.nix
    ../../modules/hermes-webui.nix
    ../../modules/users.nix
  ];

  # Host identity — these are machine-specific constants that must not be
  # shared across hosts or extracted into modules.
  networking.hostName = "nixos-hermes";
  # ZFS hostId ties the pool to this machine; changing it requires pool export/import.
  networking.hostId = "52dd4e5a";

  system.stateVersion = "25.05";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  nix.settings.trusted-users = [ "admin" ];

  services.hermes-webui = {
    enable = true;
    # password = config.sops.secrets."hermes-webui".path;  # set after first deploy
  };
}

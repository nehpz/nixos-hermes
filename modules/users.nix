{ pkgs, ... }:

{
  users.mutableUsers = false;
  users.users.root = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOQ0xpYd/EJnMyHW36xmWodb0DPoMHf4LpQAl7xheMRE"
    ];
  };
  users.users.admin = {
    isNormalUser = true;
    description = "System Admin";
    home = "/home/admin";
    createHome = true;
    homeMode = "700";
    extraGroups = [
      "wheel"
      "networkmanager"
      "hermes"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG3neF+6qsDFb1pwr06mdW0mqMcxquAGNsjbGiG/Rj23"
    ];
    # Interactive tools for working on this host over SSH.
    # Kept here rather than systemPackages — these are user conveniences,
    # not system utilities.
    packages = with pkgs; [
      bat # syntax-highlighted cat replacement
      glow # markdown renderer for the terminal
      yazi # terminal file manager
    ];
  };
  users.users.hermes = {
    description = "Hermes account";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID0inarJ3Em+01Y22ahDmJkbhevhwuFFrWyIEl0CjkzE"
    ];
  };

  # Keep the operator checkout location explicit because mutable users means
  # ad-hoc home-directory state should not be part of the host contract.
  systemd.tmpfiles.rules = [
    "d /home/admin/workspace 0755 admin users - -"
  ];
}

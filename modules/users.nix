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
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBN6C8GPyeaAKWwkSqNXzDDQEzeGQ21IWGhAa+xFqNIHlQ7uDNA/9wc8A4tXO3ckp7seY+84aXAAyCQyfrrmKSbQ= #ssh.id"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBCBs4KwCYyBZxsb02nyw9tRMsgOtfBuyM3mBh4varuvKc4JO4rzN1Iq2cXHyy0ttYIaDg52iPWlTM+O6pdpvVcE= #ssh.id"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNWfcMlHqWVodM+9A5ZnVEvw7zkDJMHW2cUw4Ru4v+8a3ot+QHH038uLkTl95SIL5XaKslAqe+gyqcZ4X6BPhtA= #ssh.id"
    ];
  };

  # Keep the operator checkout location explicit because mutable users means
  # ad-hoc home-directory state should not be part of the host contract.
  systemd.tmpfiles.rules = [
    "d /home/admin/workspace 0755 admin users - -"
  ];
}

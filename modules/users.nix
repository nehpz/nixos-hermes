{ config, ... }:

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
    extraGroups = [
      "wheel"
      "networkmanager"
      "hermes"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG3neF+6qsDFb1pwr06mdW0mqMcxquAGNsjbGiG/Rj23"
    ];
  };
  users.users.hermes = {
    description = "Hermes account";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID0inarJ3Em+01Y22ahDmJkbhevhwuFFrWyIEl0CjkzE"
    ];
  };
}

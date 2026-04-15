{ pkgs, ... }:

{
  time.timeZone = "America/Phoenix";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  networking.networkmanager.enable = true;
  networking.firewall.enable = false;

  services.power-profiles-daemon.enable = false;
  services.thermald.enable = true;
  services.printing.enable = true;
  services.xserver.videoDrivers = [ "modesetting" ];

  services.openssh.enable = true;
  services.openssh.hostKeys = [
    {
      path = "/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    curl
    wget
    git
    man
    htop
    iotop
  ];

  environment.sessionVariables = {
    # HERMES_HOME and HERMES_MANAGED are owned by the hermes-agent module;
    # do not declare them here.
    LIBVA_DRIVER_NAME = "iHD";
  };
}

{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Bake the sops-managed SSH host key into the initrd so the fingerprint is
  # stable across rebuilds. On first install, pre-place the key at
  # /mnt/etc/ssh/ssh_host_ed25519_key before running nixos-install.
  boot.initrd.secrets = {
    "/etc/ssh/ssh_host_ed25519_key" = "/etc/ssh/ssh_host_ed25519_key";
  };

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "thunderbolt"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "sr_mod"
  ];
  boot.initrd.kernelModules = [ ];

  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  boot.kernelParams = [
    "zfs.zfs_arc_max=17179869184"
    "nvme_core.default_ps_max_latency_us=0"
  ];

  boot.kernel.sysctl = {
    "vm.swappiness" = 0;
  };

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.extraInstallCommands = ''
    ${pkgs.rsync}/bin/rsync -av --delete /boot/ /boot-fallback/
  '';

  fileSystems."/" = {
    device = "rpool/root/nixos";
    fsType = "zfs";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/6A72-277A";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  fileSystems."/boot-fallback" = {
    device = "/dev/disk/by-uuid/6B49-FD17";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
      "nofail"
    ];
  };

  fileSystems."/nix" = {
    device = "rpool/nix";
    fsType = "zfs";
  };

  fileSystems."/var" = {
    device = "rpool/var";
    fsType = "zfs";
  };

  fileSystems."/var/lib/hermes" = {
    device = "rpool/data/hermes";
    fsType = "zfs";
  };

  fileSystems."/data/backup" = {
    device = "rpool/data/backup";
    fsType = "zfs";
  };

  swapDevices = [ ];

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
      intel-compute-runtime
    ];
  };
  powerManagement.cpuFreqGovernor = "schedutil";
}

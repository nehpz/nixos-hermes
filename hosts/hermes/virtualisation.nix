{ pkgs, ... }:

{
  # Container-first substrate for proving workload semantics quickly. Docker is
  # intentionally enabled on the bare-metal ZFS host now, with libvirt alongside
  # it so the same workloads can move behind a microVM boundary once the shape is
  # proven. Do not reuse this Docker storage-driver choice inside guests: guest
  # Docker should use overlay2 on ext4/xfs to avoid stacked CoW over host ZFS.
  virtualisation.docker = {
    enable = true;
    storageDriver = "zfs";
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  virtualisation.libvirtd = {
    enable = true;
    qemu.vhostUserPackages = [ pkgs.virtiofsd ];
  };

  # These memberships are root-equivalent for Docker and intentionally live with
  # the host services that create the groups rather than in portable users.nix.
  users.users.admin.extraGroups = [
    "docker"
    "libvirtd"
  ];
  users.users.hermes.extraGroups = [
    "docker"
    "libvirtd"
  ];

  environment.systemPackages = with pkgs; [
    docker-compose
    lazydocker
    virtiofsd
  ];
}

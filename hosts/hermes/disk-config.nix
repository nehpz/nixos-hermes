{
  disko.devices = {
    disk = {
      nvme0 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-eui.0025384751a0ee3b";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "fmask=0022"
                  "dmask=0022"
                ];
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };
      nvme1 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-eui.0025384841a151b4";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot-fallback";
                mountOptions = [
                  "fmask=0022"
                  "dmask=0022"
                  "nofail"
                ];
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };
    };
    zpool = {
      rpool = {
        type = "zpool";
        mode = "mirror";
        mountpoint = "none";
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          acltype = "posixacl";
          xattr = "sa";
          compression = "lz4";
          "com.sun:auto-snapshot" = "false";
        };
        datasets = {
          "root/nixos" = {
            type = "zfs_fs";
            mountpoint = "/";
            options = {
              mountpoint = "legacy";
            };
          };
          "nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options = {
              mountpoint = "legacy";
              compression = "zstd";
            };
          };
          "var" = {
            type = "zfs_fs";
            mountpoint = "/var";
            options = {
              mountpoint = "legacy";
            };
          };
          "data" = {
            type = "zfs_fs";
            options = {
              mountpoint = "none";
            };
          };
          "data/hermes" = {
            type = "zfs_fs";
            mountpoint = "/var/lib/hermes";
            options = {
              mountpoint = "legacy";
              recordsize = "16K";
            };
          };
          "data/backup" = {
            type = "zfs_fs";
            mountpoint = "/data/backup";
            options = {
              mountpoint = "legacy";
              compression = "zstd";
              recordsize = "1M";
              atime = "off";
              sync = "disabled";
            };
          };
        };
      };
    };
  };
}

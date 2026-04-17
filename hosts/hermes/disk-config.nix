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
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          # ZFS property on the pool root dataset: do not mount it anywhere.
          # This is the only place "none" belongs; disko's zpool-level
          # `mountpoint` attribute expects an absolute path or null and would
          # reject the literal string "none".
          mountpoint = "none";
          acltype = "posixacl";
          xattr = "sa";
          compression = "lz4";
        };
        datasets = {
          "root/nixos" = {
            type = "zfs_fs";
            mountpoint = "/";
            options = {
              mountpoint = "legacy";
              # Ephemeral NixOS system dataset — disable auto-snapshot here
              # only, leaving data datasets untouched so future snapshot
              # tooling can opt them in explicitly.
              "com.sun:auto-snapshot" = "false";
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

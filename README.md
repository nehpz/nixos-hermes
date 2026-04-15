# nixos-hermes

NixOS configuration for **hermes** — a dedicated bare-metal host for running
[NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) as a
personal, always-on AI assistant.

Secondary goals: learn NixOS/Nix as a discipline and leave room to run
multiple agents concurrently as capabilities grow.

---

## Hardware

| Component | Spec                                                   |
|-----------|--------------------------------------------------------|
| Host | HP Elite Mini 800 G9                                   |
| CPU | Intel Core i5-14500T (14-core, Raptor Lake)            |
| RAM | 96GB DDR5-5600                                         |
| Storage | 2 × 2TB Samsung 990 Pro NVMe SSD (ZFS mirror)          |
| GPU | None (Intel Arc iGPU only, Quick Sync / VA-API enabled) |

---

## Architecture

### Storage

ZFS mirror pool (`rpool`) spanning both NVMe drives, encrypted with a raw key
stored at `/etc/secrets/zfs.key`. Dataset layout:

```text
rpool
├── root/nixos      → /                 (legacy mount, OS root)
├── nix             → /nix              (zstd, Nix store)
├── var             → /var              (runtime state)
└── data
    ├── hermes      → /var/lib/hermes   (16K recordsize, agent home)
    └── backup      → /data/backup      (zstd, 1M records, atime off)
```

Each NVMe also carries a 1GB FAT32 ESP. The primary ESP mounts at `/boot`;
the secondary at `/boot-fallback`. On every `nixos-rebuild switch`, systemd-boot
replicates the primary ESP to the fallback via `rsync`.

ZFS ARC is capped at 16GB to leave headroom for the agent workload.

### Remote Unlock

The pool is encrypted. On each cold boot, the initrd brings up the NIC and
exposes an SSH server (port 22, same ed25519 host key as the main system).

Unlock procedure:

```bash
# initrd has no DNS resolver — use the host IP, not the hostname
ssh root@<host-ip>
# the shell auto-runs:  zfs load-key -a; killall zfs
# system continues booting
```

After unlocking, the main system comes up and `nixos-hermes` resolves normally
via your local DNS for all subsequent access.

### Secrets Management

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix) and
[age](https://github.com/FiloSottile/age). The age host key lives at
`/etc/secrets/age.key` (generated once, placed manually during bootstrap).
Encrypted secrets live under `hosts/hermes/secrets/` and are decrypted at activation
time.

### Hermes Agent

Declared via the official `hermes-agent.nixosModules.default` NixOS module,
sourced from `github:NousResearch/hermes-agent`. Agent state persists in
`rpool/data/hermes` (mounted at `/var/lib/hermes`). The `HERMES_HOME`
environment variable points into that dataset.

---

## Network

| Property | Value |
|----------|-------|
| Hostname | `nixos-hermes` |
| IP | Static, gateway-enforced (subject to change) |
| Firewall | Disabled — the network perimeter is trusted |

The specific IP is not hardcoded in this configuration and is managed at the
gateway. Update your SSH config when it changes.

---

## Repository Layout

```text
nixos-hermes/
├── flake.nix                          # Flake inputs/outputs, host definition
├── .github/workflows/flakehub-publish-rolling.yml  # CI: publish to FlakeHub on push to main
├── .sops.yaml                         # sops encryption rules (age keys)
├── .secrets/                          # gitignored — plaintext secrets (local only)
│   └── hermes-secrets.yaml            # template; encrypt before committing
├── hosts/
│   └── hermes/
│       ├── default.nix                # host entry: identity constants + imports
│       ├── hardware.nix               # boot, initrd, filesystems, kernel, GPU
│       ├── sops.nix                   # SOPS secret bindings
│       ├── disk-config.nix            # disko layout (install-time only)
│       └── secrets/                   # encrypted secret files (committed)
└── modules/
    ├── system.nix                     # locale, tz, networking, packages, sudo
    ├── hermes-agent.nix               # hermes service declaration
    └── users.nix                      # immutable user + SSH key definitions
```

---

## Bootstrapping the Host

> These steps are performed once from the NixOS live ISO. The host must be
> reachable over SSH.

### 1. Partition, Format, and Create the ZFS Pool

```bash
nix run github:nix-community/disko/latest -- \
  --mode disko hosts/hermes/disk-config.nix
```

Disko partitions both NVMes, formats the ESPs, and creates `rpool` as a mirror.
It does **not** mount legacy-mountpoint ZFS datasets.

### 2. Mount the ZFS Datasets

```bash
mount -t zfs rpool/root/nixos /mnt
mkdir -p /mnt/{nix,var,var/lib/hermes,data/backup}
mount -t zfs rpool/nix /mnt/nix
mount -t zfs rpool/var /mnt/var
mount -t zfs rpool/data/hermes /mnt/var/lib/hermes
mount -t zfs rpool/data/backup /mnt/data/backup
```

### 3. Place the Age Key

### 3. Place the Age Key

```bash
mkdir -p /mnt/etc/secrets
# Copy the age private key generated with `age-keygen`:
cp /path/to/age.key /mnt/etc/secrets/age.key
chmod 600 /mnt/etc/secrets/age.key
```

> **Note:** sops-nix is a systemd runtime service — it does not run during
> `nixos-install` activation. The SSH host key and age key must both be
> pre-placed manually (steps 3 and 4 below) before running `nixos-install`.


### 4. Pre-Place the SSH Host Key

```bash
mkdir -p /mnt/etc/ssh
SOPS_AGE_KEY_FILE=/etc/secrets/age.key nix run nixpkgs#sops -- \
  --decrypt --output-type binary \
  hosts/hermes/secrets/ssh_host_ed25519_key.enc > /mnt/etc/ssh/ssh_host_ed25519_key
chmod 600 /mnt/etc/ssh/ssh_host_ed25519_key
```

### 5. Install the Flake

```bash
nixos-install --flake github:nehpz/nixos-hermes#nixos-hermes
```

### 6. Reboot and Verify

```bash
reboot
# Once the initrd SSH server is up:
ssh root@<host-ip>
# Unlock runs automatically from .profile; system boots fully
```

---

## Applying the Changes

There is no automated deployment step yet. After pushing to `main`, apply changes
manually:

```bash
ssh admin@nixos-hermes
sudo nixos-rebuild switch --flake github:nehpz/nixos-hermes#nixos-hermes
```

Or build locally and push the closure:

```bash
nixos-rebuild switch --flake .#nixos-hermes \
  --target-host admin@nixos-hermes --use-remote-sudo
```

---

## CI

GitHub Actions publishes the flake to FlakeHub on every push to `main` using the
[DeterminateSystems](https://determinate.systems/) stack. Requires one repository
secret: `FLAKEHUB_TOKEN` (set under Settings → Secrets and variables → Actions).

---

## Design Decisions

Architectural decisions are documented as ADRs in [`docs/adr/`](docs/adr/).

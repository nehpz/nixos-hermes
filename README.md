# nixos-hermes

NixOS configuration for **hermes** — a dedicated bare-metal host for running
[NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) as a
personal, always-on AI assistant. The machine is a production-grade homelab
node: no pager-duty SLAs, but downtime means no value.

Secondary goals: learn NixOS/Nix as a discipline, and leave room to run
multiple agents concurrently as capabilities grow.

---

## Hardware

| Component | Spec |
|-----------|------|
| Host | HP Elite Mini 800 G9 |
| CPU | Intel Core i5-14500T (14-core, Raptor Lake) |
| RAM | 96 GB DDR5-5600 |
| Storage | 2 × 2 TB Samsung 990 Pro NVMe (ZFS mirror) |
| GPU | None (Intel Arc iGPU only, Quick Sync / VA-API enabled) |

---

## Architecture

### Storage

ZFS mirror pool (`rpool`) spanning both NVMe drives, encrypted with a raw key
stored at `/etc/secrets/zfs.key`. Dataset layout:

```
rpool
├── root/nixos      → /           (legacy mount, OS root)
├── nix             → /nix        (zstd, Nix store)
├── var             → /var        (runtime state)
└── data
    ├── hermes      → /var/lib/hermes   (16K recordsize, agent home)
    └── backup      → /data/backup      (zstd, 1M records, atime off)
```

Each NVMe also carries a 1 GB FAT32 ESP. The primary ESP mounts at `/boot`;
the secondary at `/boot-fallback`. On every `nixos-rebuild switch`, systemd-boot
replicates the primary ESP to the fallback via `rsync`.

ZFS ARC is capped at 16 GB to leave headroom for the agent workload.

### Remote Unlock

The pool is encrypted. On each cold boot, the initrd brings up the NIC and
exposes an SSH server (port 22, same ed25519 host key as the main system).
Unlock procedure:

```
# initrd has no DNS resolver — use the host IP, not the hostname
ssh root@<host-ip>
# the shell auto-runs:  zfs load-key -a; killall zfs
# system continues booting
```

After unlock, the main system comes up and `nixos-hermes` resolves normally
via your local DNS for all subsequent access.

### Secrets

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix) and
[age](https://github.com/FiloSottile/age). The age host key lives at
`/etc/secrets/age.key` (generated once, placed manually during bootstrap).
Encrypted secrets live under `nixos/secrets/` and are decrypted at activation
time.

Currently managed secrets:

| Secret | Purpose |
|--------|---------|
| `ssh_host_ed25519_key` | Stable SSH host identity across rebuilds |
| `codex_auth_json` | OpenAI Codex authentication for hermes-agent |
| `elevenlabs_api_key` | ElevenLabs TTS for hermes-agent voice output |
| `discord_bot_token` | Discord integration for hermes-agent |

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

```
nixos-hermes/
├── flake.nix                            # Flake inputs/outputs, host definition
├── .github/workflows/nix-ci.yml         # CI: flake check on push to main
├── .sops.yaml                           # sops encryption rules (age keys)
├── .secrets/                            # gitignored — plaintext secrets (local only)
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

## Bootstrap (First Install)

> These steps are performed once from the NixOS live ISO. The host must be
> reachable over SSH.

### 1. Partition and format

```bash
nix run github:nix-community/disko -- \
  --mode disko hosts/hermes/disk-config.nix
```

### 2. Place the ZFS encryption key

```bash
mkdir -p /mnt/etc/secrets
# Copy your pre-generated raw key:
dd if=/dev/urandom of=/mnt/etc/secrets/zfs.key bs=32 count=1
# Then import and load:
zpool import -d /dev/disk/by-id rpool
zfs load-key -L file:///mnt/etc/secrets/zfs.key rpool
```

### 3. Place the age key

```bash
mkdir -p /mnt/etc/secrets
# Copy the age private key generated with `age-keygen`:
cp /path/to/age.key /mnt/etc/secrets/age.key
chmod 600 /mnt/etc/secrets/age.key
```

### 4. Install

```bash
nixos-install --flake github:nehpz/nixos-hermes#nixos-hermes
```

### 5. Reboot and unlock

```bash
reboot
# Once the initrd SSH server is up:
ssh root@<host-ip>
# Unlock runs automatically from .profile; system boots fully
```

---

## Applying Changes

There is no automated deploy step yet. After pushing to `main` (CI validates
the flake), apply changes manually:

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

GitHub Actions runs `nix flake check` on every push to `main` using the
[DeterminateSystems](https://determinate.systems/) Nix stack and FlakeHub
binary cache. No secrets or deploy credentials are required in CI.

---

## Design Decisions

- **Immutable users** (`mutableUsers = false`): all user configuration is
  declarative; no password-based login.
- **Firewall disabled**: trusted LAN segment; simplifies agent networking.
- **Dual ESP + rsync replication**: survives a single drive failure without
  losing bootability.
- **No swap**: 96 GB RAM makes swap unnecessary; `vm.swappiness = 0` prevents
  kernel speculation.
- **NVMe power management disabled** (`nvme_core.default_ps_max_latency_us=0`):
  trades idle power for consistent low-latency I/O.
- **`schedutil` CPU governor**: lets the kernel adapt frequency to load; more
  responsive than `powersave`, more efficient than `performance`.

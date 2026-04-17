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

ZFS mirror pool (`rpool`) spanning both NVMe drives. Dataset layout:

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

Disk layout, partitioning, and the generated `fileSystems.*` entries are all
driven from `hosts/hermes/disk-config.nix` via the
[disko](https://github.com/nix-community/disko) NixOS module.

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
│       ├── disk-config.nix            # disko layout (imported; generates fileSystems.*)
│       ├── hardware.nix               # boot, initrd, kernel, GPU, ZFS services
│       ├── sops.nix                   # SOPS secret bindings
│       └── secrets/                   # encrypted secret files (committed)
└── modules/
    ├── system.nix                     # locale, tz, networking, packages, sudo
    ├── hermes-agent.nix               # hermes service declaration
    └── users.nix                      # immutable user + SSH key definitions
```

---

## Bootstrapping the Host

Two supported paths. Prefer **nixos-anywhere** for a headless remote install;
fall back to the **Live CD** flow only when SSH to the target is unavailable.

### Prerequisites

The target must be reachable over SSH as `root` (or a passwordless-sudo user)
from your workstation, running any modern Linux kernel. Prep depends on the
target's starting state:

- **Already running Linux (any distro):** confirm `sshd` is up, your key is in
  `~/.ssh/authorized_keys`, and the machine has outbound internet. Nothing else
  to install — nixos-anywhere will kexec over it.
- **Bare-metal, no OS (e.g. a fresh hermes host):** boot the NixOS minimal
  installer ISO from USB, set a root password with `passwd`, note the IP with
  `ip -4 addr`, and `ssh-copy-id root@<target-ip>` from your workstation.
  Console access is needed once; afterwards the install proceeds over SSH.
- **Has IPMI/BMC with remote media:** mount a Linux rescue ISO via the BMC
  web UI and authorize your key through its console (not applicable to the
  hermes host, which has no BMC).

From your workstation, with an age private key available locally:

```bash
mkdir -p extra-files/etc/secrets
cp /path/to/age.key extra-files/etc/secrets/age.key
chmod 400 extra-files/etc/secrets/age.key

nix run .#nixos-anywhere -- \
  --flake .#nixos-hermes \
  --extra-files extra-files \
  root@<target>

find extra-files -type f -exec shred -u {} +
rm -rf extra-files
```

This kexec's the target into the NixOS installer, runs disko from
`hosts/hermes/disk-config.nix` to partition and mount, installs, and reboots.
The age key is seeded into `/etc/secrets/age.key` on the installed system so
sops-nix can decrypt secrets on first activation.

Full install instructions, including the Live CD fallback and the bootloader
workaround, live in [`AGENTS.md`](AGENTS.md#first-install).

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

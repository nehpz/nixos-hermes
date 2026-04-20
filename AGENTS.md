# AGENTS.md — Working Context for AI Agents

This file is the authoritative guide for AI agents (Claude, Codex, etc.) working on this repository. Read it before touching any file.

## Project in One Sentence

A fully declarative NixOS flake configuration for a bare-metal AI agent host running `hermes-agent` (NousResearch) as a systemd service, delivering a personal, always-on assistant.

## Repository Layout

```text
nixos-hermes/
├── flake.nix                            # flake inputs/outputs, host definition
├── .github/workflows/flakehub-publish-rolling.yml # CI: publish to FlakeHub on push to main
├── .sops.yaml                           # sops encryption policy (age)
├── .secrets/                            # GITIGNORED — plaintext secrets, local only
│   └── hermes-secrets.yaml              # never commit; encrypt before use
├── hosts/
│   └── hermes/
│       ├── default.nix                  # host entry: identity constants + imports
│       ├── disk-config.nix              # disko layout (imported; generates fileSystems.*)
│       ├── hardware.nix                 # boot, initrd, kernel, GPU, ZFS services (filesystems via disko)
│       ├── provision.nix                # host-specific activation scripts (one-shot provisioning + recurring refresh)
│       ├── sops.nix                     # sops-nix secret bindings (host-specific)
│       └── secrets/                     # committed SOPS-encrypted files
├── modules/
│   ├── system.nix                       # locale, tz, networking, packages, sudo
│   ├── hermes-agent.nix                 # hermes service declaration
│   ├── packages.nix                     # nixpkgs overlays + NixOS packaging workarounds
│   └── users.nix                        # immutable user + SSH key declarations
└── packages/
    └── agent-browser/
        └── default.nix                  # prebuilt platform binary from npm tarball
```

---

## Technology Stack

| Layer | Tool |
|-------|------|
| OS | NixOS (nixpkgs unstable via FlakeHub `NixOS/nixpkgs/0`) |
| Nix runtime | Determinate Nix (via `determinate` flake input) |
| Secret management | sops-nix + age |
| Storage | ZFS (`rpool`, mirror) |
| Boot | systemd-boot, dual ESP |
| Agent service | `hermes-agent.nixosModules.default` |
| CI | GitHub Actions + DeterminateSystems stack |

---

## Coding Conventions

### Nix Style

- Module function heads use named args: `{ config, pkgs, lib, ... }:`
- One logical concern per file; do not conflate hardware and service config.
- Comments explain *why*, not *what* the code already says.
- Prefer `lib.mkDefault` only at genuine override boundaries; omit where the value is unconditional.

### Secrets

- **Never commit plaintext secrets.** `.secrets/` is `.gitignore`d; it exists only for local templating.
- The committed encrypted secrets live under `hosts/hermes/secrets/`.
- The `sops age` key is `/etc/secrets/age.key` on the host. The corresponding public key is registered in `.sops.yaml`. Do not change the public key in `.sops.yaml` without re-encrypting every secret file.
- `.secrets/hermes-secrets.yaml` is the plaintext template (`gitignored`). Workflow: edit locally → `sops --encrypt .secrets/hermes-secrets.yaml > hosts/hermes/secrets/hermes-secrets.yaml` → commit the encrypted file → never commit the plaintext.
- When adding a new secret key: add it to `.secrets/hermes-secrets.yaml`, add the `sops.secrets.<name>` binding in `hosts/hermes/sops.nix`, then re-encrypt.

### Users

- `users.mutableUsers = false` — the NixOS activation will reject any user state not described in `users.nix`. Do not add users imperatively on the host.
- Authentication is via SSH key only. Do not add password hashes unless explicitly requested.
  requested.
- `admin` has `wheel` and should have `security.sudo.wheelNeedsPassword = false` set (or equivalent) since there is no password configured.

### Git Hygiene

> **Never `git push` autonomously.** Commit is the limit of unsupervised git action. Always stop after `git commit` and wait for explicit instruction to push.

- The repo is **public**. Never commit SSH private keys, age private keys, plaintext secrets, IP-to-identity mappings, or personal information.
- The public SSH authorized keys already in the repo are acceptable (by design).
- Commit messages: imperative mood, present tense, ≤72 chars subject line.

---

## What Each Nix File Owns

### `flake.nix`

*Single host output: `nixosConfigurations.nixos-hermes`.*

- Manages input pins.
- Do not add multiple hosts without a corresponding refactor of the module tree.

*`nixosModules.default` convention*

- In flake outputs, `.default` is the canonical name for a flake's primary export of a given type — analogous to `packages.default`.
- `Determinate.nixosModules.default` and `hermes-agent.nixosModules.default` are values from two entirely separate flakes; naming collision is impossible.
- The NixOS module system merges all entries in the `modules` list regardless of where they came from.

*`Determinate.nixosModules.default` owns `nix.package`.*

- Do not set `nix.package` elsewhere in the module tree — the `Determinate` module manages `nix.package`.
- Duplicate declarations will cause an evaluation error.

*Flake inputs use FlakeHub URLs where possible, with fallback to GitHub.*

- `NixOS/nixpkgs/0` is FlakeHub's semver alias for nixpkgs unstable (`0` = pre-1.0 channel).
- FlakeHub Cache works best when inputs are FlakeHub-sourced.

> Do not switch a FlakeHub-published input back to a raw GitHub URL.

- Exceptions must be documented and currently include:
  - `nousresearch/hermes-agent`
    - Not published to FlakeHub at this time.
  - `nix-community/nixos-anywhere`
    - No release consumable as a flake input (`https://flakehub.com/f/nix-community/nixos-anywhere/*` returns 404 on archive fetch).
    - Pinned via `flake.lock` so bootstrap runs are reproducible; revisit when upstream publishes a version.

### `hosts/hermes/default.nix`

*Host entry point.*

- Contains machine-specific identity constants (`hostName`, `hostId`, `stateVersion`, `hostPlatform`) and the import list. Nothing else.
- These constants must never be extracted into shared modules.

### `hosts/hermes/hardware.nix`

*Everything tied to physical hardware.*

- Includes: boot, initrd, kernel, GPU, and bootloader configuration.
- Host-specific storage service options (e.g. `services.zfs.autoScrub`, `services.zfs.trim`) also live here because they only apply to this host's ZFS configuration and must not leak into the portable `modules/system.nix`.
- Filesystem mounts themselves are generated by `disko` from `disk-config.nix`, not declared here.

### `hosts/hermes/disk-config.nix`

*Declarative disk layout consumed by `disko`.*

- Describes GPT partitions and the ZFS pool/dataset structure.
- Imported as a NixOS module via `disko.nixosModules.default`, so `disko` generates `fileSystems.*` entries at evaluation time from the `mountpoint = "..."` attributes on each partition and dataset.

> Do not declare `fileSystems.*` manually in `hardware.nix` — that would duplicate what `disko` produces.

At install time:
  - The same file is also consumed by `nix run .#disko -- --mode disko hosts/hermes/disk-config.nix`.
  - Exposed as a flake app so the CLI uses the same `flake.lock` pin as the NixOS module, eliminating module/CLI version skew.

After first install:
  - The partition/pool sections are effectively reference documentation.
  - Changing them does not reformat disks, but the `mountpoint` attributes remain live: they control mounting on every rebuild.

### `hosts/hermes/sops.nix`

*Maps SOPS-encrypted files to runtime paths.*

- Lives alongside `secrets/` so that `./secrets/...` paths resolve correctly.
- The `sops age` key path (`/etc/secrets/age.key`) must not change without updating this file.

### `hosts/hermes/provision.nix`

*Host-specific activation scripts. Two categories:*

- **One-shot provisioning:** activation scripts with a file-existence guard that run once on first boot to seed runtime state. Rebuilds do not clobber runtime-evolved state. To re-provision: delete the target file on the host, then rebuild.
- **Recurring refresh:** activation scripts with no guard that run on every activation. Used for credentials and other state that must stay in sync with sops secrets.
- Lives in `hosts/hermes/` (not `modules/`) because provisioning is host-specific,
  not portable across hosts.
- To re-provision a file: delete it on the host, then rebuild.

### `modules/packages.nix`

*nixpkgs overlays and NixOS packaging workarounds.*

- Owns the nixpkgs overlay that injects packages not yet in the pinned channel.
  Add new local packages here (see `packages/`) until they land upstream.
- Also owns workarounds for NixOS packaging behaviour that affect services on this
  host (e.g. the `opusCtypesShim` for CPython's patched `ctypes.util.find_library`).
- Exposes shims via the overlay (e.g. `pkgs.opusCtypesShim`) so service modules
  can consume them without coupling to this file directly.

### `packages/<name>/default.nix`

*Local package derivations.*

- One directory per package; derivation fetches prebuilt binaries where available.
- Injected into nixpkgs via the overlay in `modules/packages.nix`.
- Versioned by Renovate; extract to a shared flake (`nehpz/nursery`) when multi-host.


### `modules/system.nix`

*Base system settings.*

- Includes: locale, timezone, networking, openssh, sudo, packages, and session variables.
- No host-specific values.

### `modules/hermes-agent.nix`

*The `hermes-agent` service declaration.*

- All `services.hermes-agent.*` options belong here.
- Secrets are referenced by name from the `sops` bindings.

### `modules/users.nix`

*Immutable user definitions.*

- The only place user accounts and authorized SSH keys should appear.
- Lives in `modules/` because it is portable across hosts.

---

## Testing and Validation

### Local Check (No Host Needed)

```bash
nix flake check
```

### Dry-Run Build (Evaluates but Does Not Activate)

```bash
nixos-rebuild dry-build --flake .#nixos-hermes
```

## First Install

A dedicated runbook is available in `docs/runbooks/FIRST_INSTALL.md`.

---

## Hermes Agent Configuration

See `docs/guides/HERMES_AGENT_CONFIGURATION.md` for details.

---

## Deployment Topology

```text
GitHub (nehpz/nixos-hermes)
    │
    ├─ push to main → CI: publish flake to FlakeHub
    │
    └─ manual: nixos-rebuild switch → nixos-hermes
                                           │
                                    ZFS mirror rpool
```

The host IP is static and enforced at the gateway. If it changes, update your SSH config; the NixOS configuration itself uses hostnames, not IPs.

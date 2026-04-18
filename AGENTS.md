# AGENTS.md — Working Context for AI Agents

This file is the authoritative guide for AI agents (Claude, Codex, etc.)
working on this repository. Read it before touching any file.

---

## Project in One Sentence

A fully declarative NixOS flake configuration for a bare-metal AI agent host
running `hermes-agent` (NousResearch) as a systemd service, delivering a personal, always-on assistant.

---

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
│       ├── sops.nix                     # sops-nix secret bindings (host-specific)
│       └── secrets/                     # committed SOPS-encrypted files
└── modules/
    ├── system.nix                       # locale, tz, networking, packages, sudo
    ├── hermes-agent.nix                 # hermes service declaration
    └── users.nix                        # immutable user + SSH key declarations
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
- Prefer `lib.mkDefault` only at genuine override boundaries; omit where the
  value is unconditional.
- Comments explain *why*, not *what* the code already says.

### Secrets

- **Never commit plaintext secrets.** `.secrets/` is `.gitignore`d; it exists
  only for local templating.
- The committed encrypted secrets live under `hosts/hermes/secrets/`.
- The `sops age` key is `/etc/secrets/age.key` on the host. The corresponding
  public key is registered in `.sops.yaml`. Do not change the public key in
  `.sops.yaml` without re-encrypting every secret file.
- `.secrets/hermes-secrets.yaml` is the plaintext template (`gitignored`). Workflow:
  edit locally → `sops --encrypt .secrets/hermes-secrets.yaml > hosts/hermes/secrets/hermes-secrets.yaml`
  → commit the encrypted file → never commit the plaintext.
- When adding a new secret key: add it to `.secrets/hermes-secrets.yaml`, add the
  `sops.secrets.<name>` binding in `hosts/hermes/sops.nix`, then re-encrypt.

### Users

- `users.mutableUsers = false` — the NixOS activation will reject any user
  state not described in `users.nix`. Do not add users imperatively on the host.
- Authentication is via SSH key only. Do not add password hashes unless explicitly
  requested.
- `admin` has `wheel` and should have `security.sudo.wheelNeedsPassword = false`
  set (or equivalent) since there is no password configured.

### Git Hygiene

- The repo is **public**. Never commit SSH private keys, age private keys,
  plaintext secrets, IP-to-identity mappings, or personal information.
- The public SSH authorized keys already in the repo are acceptable (they are
  public by design).
- Commit messages: imperative mood, present tense, ≤72 chars subject line.
- **Never `git push` autonomously.** Commit is the limit of unsupervised git
  action. Always stop after `git commit` and wait for explicit instruction to push.

---

## What Each File Owns

### `flake.nix`

Single host output: `nixosConfigurations.nixos-hermes`. Manages input pins.
Do not add multiple hosts without a corresponding refactor of the module tree.

**`nixosModules.default` convention:** In flake outputs, `.default` is the
canonical name for a flake's primary export of a given type — analogous to
`packages.default`. `determinate.nixosModules.default` and
`hermes-agent.nixosModules.default` are values from two entirely separate
flakes; naming collision is impossible. The NixOS module system merges all
entries in the `modules` list regardless of where they came from.

**`determinate.nixosModules.default` owns `nix.package`.** Do not set
`nix.package` elsewhere in the module tree — the Determinate module manages
it. Duplicate declarations will cause an evaluation error.

**Flake inputs use FlakeHub URLs where possible.** `NixOS/nixpkgs/0` is FlakeHub's
semver alias for nixpkgs unstable (`0` = pre-1.0 channel). FlakeHub Cache works
best when inputs are FlakeHub-sourced; do not switch a FlakeHub-published input
back to a raw GitHub URL. Two inputs are exceptions:

- `hermes-agent` (NousResearch) is not published to FlakeHub at all.
- `nixos-anywhere` (nix-community) has a FlakeHub landing page, but no
  releases are currently consumable as a flake input (`https://flakehub.com/f/nix-community/nixos-anywhere/*`
  returns 404 on archive fetch); revisit when upstream publishes a version.

Both use `github:` URLs and are still pinned via `flake.lock`.

### `hosts/hermes/default.nix`

Host entry point. Contains machine-specific identity constants (`hostName`,
`hostId`, `stateVersion`, `hostPlatform`) and the import list. Nothing else.
These constants must never be extracted into shared modules.

### `hosts/hermes/hardware.nix`

Everything tied to physical hardware: boot, initrd, kernel, GPU, and bootloader
configuration.

Host-specific storage service options (e.g. `services.zfs.autoScrub`,
`services.zfs.trim`) also live here because they only apply to this host's
ZFS configuration and must not leak into the portable `modules/system.nix`.
Filesystem mounts themselves are generated by disko from `disk-config.nix`,
not declared here.

### `hosts/hermes/disk-config.nix`

Declarative disk layout consumed by disko. Describes GPT partitions and the
ZFS pool/dataset structure. Imported as a NixOS module via
`disko.nixosModules.default`, so disko generates `fileSystems.*` entries at
evaluation time from the `mountpoint = "..."` attributes on each partition
and dataset. Do not declare `fileSystems.*` manually in `hardware.nix` — that
would duplicate what disko produces.

At install time the same file is also consumed by `nix run .#disko -- --mode
disko hosts/hermes/disk-config.nix` — exposed as a flake app so the CLI uses
the same `flake.lock` pin as the NixOS module, eliminating module/CLI version
skew. After first install, the partition/pool sections are effectively
reference documentation — changing them does not reformat disks — but the
`mountpoint` attributes remain live: they control mounting on every rebuild.

### `hosts/hermes/sops.nix`

Maps SOPS-encrypted files to runtime paths. Lives alongside `secrets/` so that
`./secrets/...` paths resolve correctly. The `sops age` key path (`/etc/secrets/age.key`)
must not change without updating this file.

### `modules/system.nix`

Base system settings: locale, timezone, networking, openssh, sudo, packages,
and session variables. No host-specific values.

### `modules/hermes-agent.nix`

The `hermes-agent` service declaration. All `services.hermes-agent.*` options
live here. Secrets are referenced by name from the sops bindings.

### `modules/users.nix`

Immutable user definitions. The only place user accounts and authorized SSH
keys should appear. Lives in `modules/` because it is portable across hosts.

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

### First Install

Two paths are supported. **Prefer nixos-anywhere** for a headless host: you
never need to touch a keyboard on the target. Fall back to the Live CD flow
only when SSH to the target is not available (no IPMI, no rescue OS).

#### Path A: nixos-anywhere (recommended, headless)

##### What nixos-anywhere needs

Exactly one thing: SSH access to the target as `root` (or as a user with
passwordless `sudo`), running any reasonably current Linux kernel. From there
it kexecs into a NixOS installer, partitions via `disk-config.nix`, installs
the flake, and reboots — without you touching the physical machine again.

The age private key is seeded onto the target during install via
`--extra-files`, so sops-nix can decrypt secrets on first activation.

##### Getting the target to an SSH-reachable Linux state

The prep required depends on the target's starting state.

**State 1 — target is already running a Linux distro (Ubuntu, Debian, Fedora,
etc.).**

This is the easiest path; nothing to install. Just confirm:

- `sshd` is running and reachable from your workstation.
- Your workstation's public key is in `~/.ssh/authorized_keys` for either
  `root` or a user with passwordless `sudo`.
- The machine has outbound internet (nixos-anywhere fetches nixpkgs during
  install).

nixos-anywhere will kexec over the existing distro and wipe the disks per
`disk-config.nix`, so there is nothing on the current install worth
preserving.

**State 2 — target is bare-metal with no OS.**

Two routes, depending on whether vPro / Intel AMT is provisioned on the host.

*State 2a — USB boot (one-time physical console access):*

1. On your workstation, download the NixOS minimal installer ISO
   (https://nixos.org/download/#nixos-iso) or the Determinate Nix installer
   ISO — any standard NixOS live ISO works.
2. Write it to a USB stick (e.g. `dd if=nixos-minimal-*.iso of=/dev/diskN bs=4M`,
   or use Etcher / Rufus).
3. Plug USB + monitor + keyboard into the target; boot from USB.
4. At the installer prompt, set a temporary root password:
   ```bash
   sudo passwd root
   ```
5. Confirm `sshd` is running (it is, on recent installer ISOs) and find the
   target's IP:
   ```bash
   ip -4 addr show | grep inet
   ```
6. From your workstation, copy your key in once (using the password from step
   4); after this, unplug monitor + keyboard and finish headlessly:
   ```bash
   ssh-copy-id root@<target-ip>
   ```

Alternatively, build a custom installer ISO with your SSH key baked in
(`nixos-generators -f iso ...`). For a one-off reprovision, `ssh-copy-id` is
faster.

*State 2b — Intel vPro / AMT IDE-R (fully remote after one-time MEBx setup):*

The hermes host (HP Elite Mini 800 G9, appropriate SKU) includes Intel vPro.
Once AMT is provisioned in MEBx, there is no further need for a USB stick,
monitor, or keyboard on the target — every reprovision is pure-network.

One-time physical setup (only required the first time, or after an AMT reset):

1. Power on the target; press `Ctrl-P` at POST to enter the Intel ME BIOS
   Extension (MEBx).
2. Change the default MEBx password, enable AMT, enable remote access,
   configure the network profile (DHCP is fine on a trusted LAN).
3. Save and exit. Note the AMT IP / hostname and the new MEBx password —
   store both in your workstation password manager.

Per reprovision (fully remote):

1. On your workstation, install an AMT client: MeshCommander (legacy but
   reliable), [MeshCentral](https://meshcentral.com/), or
   [wsman-cli](https://github.com/Openwsman/openwsman). MeshCommander's
   IDE-R dialog is the most discoverable.
2. Download the NixOS minimal / Determinate Nix installer ISO to the
   workstation (same file that would otherwise go on the USB stick).
3. Connect to the target's AMT interface (ports 16992–16995) using the MEBx
   password.
4. Mount the ISO via **Storage Redirection → IDE-R** (or USB-R on AMT ≥ 16).
   Set one-time boot override to "CD/DVD".
5. Trigger an AMT power-cycle. The target now boots the installer from the
   workstation-hosted ISO over the network.
6. Open the AMT **KVM** (VNC-over-AMT) or **Serial-over-LAN** session to reach
   the installer's shell — same steps 4–6 as State 2a (set root password,
   `ip addr`, `ssh-copy-id` from workstation).
7. Close the AMT session, detach the IDE-R media, and run `nixos-anywhere` as
   normal.

Caveats:

- IDE-R ISO size limits depend on AMT firmware; ISOs < 4 GB work on
  essentially all AMT versions, which covers both NixOS minimal and
  Determinate Nix.
- AMT ports 16992–16995 must be reachable from your workstation. Some
  corporate networks block them; confirm before committing to this route.
- AMT KVM is hardware-accelerated video redirection, not an SSH-like
  terminal. Type the key-authorization commands carefully; there is no
  copy-paste unless your client supports it.

**State 3 — target has IPMI/iDRAC/BMC with remote media.**

Not applicable to the hermes host (HP Elite Mini has no dedicated BMC;
vPro/AMT is the closest equivalent and is covered in State 2b). For other
deployments: mount a Linux rescue ISO (SystemRescue, Ubuntu Live, or the
NixOS minimal installer) via the BMC web UI, then authorize your SSH key
as in state 2a.

##### Workstation prerequisites

On the machine running `nix run .#nixos-anywhere`:

- A clone of this repo with the flake `flake.lock` committed.
- The age private key for this host available at some local path.
- An SSH agent or key that authenticates against whatever you set up on the
  target above.
- Outbound SSH to the target on port 22 (nixos-anywhere uses SSH only).

##### Run the install

Run from your workstation checkout of this repo:

```bash
# 1. Stage the age key at the exact layout it must land in on the target.
#    Everything under extra-files/ is rsync'd to / on the installed system.
mkdir -p extra-files/etc/secrets
cp /path/to/age.key extra-files/etc/secrets/age.key
chmod 400 extra-files/etc/secrets/age.key

# 2. Kexec the target (if not already NixOS) into the NixOS installer, run
#    disko from hosts/hermes/disk-config.nix, install, and reboot.
nix run .#nixos-anywhere -- \
  --flake .#nixos-hermes \
  --extra-files extra-files \
  root@<target-ip-or-host>

# 3. Securely wipe and remove the plaintext age key staging dir. Plain `rm`
#    leaves the key recoverable on many filesystems; shred overwrites first.
#    extra-files/ is gitignored but must not linger as recoverable plaintext.
find extra-files -type f -exec shred -u {} +
rm -rf extra-files
```

After the first successful install, subsequent changes use the normal `Apply
to Host` flow below — nixos-anywhere is only for bootstrapping or re-imaging.

#### Path B: Live CD / manual nixos-install (fallback)

Use this only when you cannot SSH into the target before install. Boot the
NixOS installer ISO on the target and run:

```bash
# 1. Place the age private key on the live environment.
mkdir -p /etc/secrets
cp /path/to/age.key /etc/secrets/age.key

# 2. Clone the repo.
nix shell nixpkgs#git -c git clone https://github.com/nehpz/nixos-hermes /root/nixos-hermes
cd /root/nixos-hermes

# 3. Partition, format, and mount every filesystem under /mnt in one shot.
# disko reads disk-config.nix, destroys existing layouts on the target disks,
# creates GPT + ESPs + zpool + datasets, and mounts everything at /mnt
# according to the mountpoint attributes. `.#disko` uses the lockfile-pinned
# disko, matching the version the NixOS module was evaluated against.
nix run .#disko -- --mode disko hosts/hermes/disk-config.nix

# 4. Pre-place the age key inside the target root so sops-nix can decrypt
# secrets during first activation.
mkdir -p /mnt/etc/secrets
cp /etc/secrets/age.key /mnt/etc/secrets/age.key

# 5. Install. Everything else (hostname, users, services, bootloader) is
# declarative.
nixos-install --flake github:nehpz/nixos-hermes#nixos-hermes \
  --option extra-substituters https://cache.flakehub.com \
  --option extra-trusted-public-keys 'cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM='

# 6. Sanity-check that the bootloader was written to the ESP.
ls /mnt/boot/nixos/
```

The `extra-substituters` flags are only required for the initial install. Once
Determinate Nix v3.6.0 or later is running on the host, subsequent `nixos-rebuild`
runs need no extra options.

**If `nixos-install` fails at the bootloader step** with an empty or missing
`/boot`, apply the manual bootloader install below. This has historically been
needed on this host because NixOS activation can remove the `/boot` mountpoint
from the ZFS root before `bootctl install` runs. Option 2 (disko as a NixOS
module) may have fixed the root cause; test a clean install before assuming the
workaround is still required.

```bash
# Re-mount the ESP and enter a chroot that bypasses nixos-enter's activation.
mkdir -p /mnt/boot
mount /dev/disk/by-partlabel/disk-nvme0-ESP /mnt/boot
mount --bind /proc /mnt/proc
mount --bind /dev  /mnt/dev
mount --bind /sys  /mnt/sys
mount -t tmpfs none /mnt/run

NIXOS_INSTALL_BOOTLOADER=1 \
  chroot /mnt /nix/var/nix/profiles/system/bin/switch-to-configuration boot

ls /mnt/boot/nixos/    # must contain files
```

### Apply to Host

```bash
# Build and activate on the host directly:
ssh admin@nixos-hermes 'sudo nixos-rebuild switch --flake github:nehpz/nixos-hermes#nixos-hermes'

# Or push from local checkout:
nixos-rebuild switch --flake .#nixos-hermes \
  --target-host admin@nixos-hermes \
  --build-host  admin@nixos-hermes \
  --use-remote-sudo
```

CI publishes the flake to FlakeHub on every push to `main`. There is no automated deploy; all applies are manual.


---

## Invariants — Do Not Break

- **Pool name `rpool` is fixed.** The ZFS hostId (`52dd4e5a`) ties the pool to
  this host. Changing either requires pool export/import.
- **The age public key in `.sops.yaml`** must match the private key at
  `/etc/secrets/age.key` on the host. They are a matched pair generated once,
  and hermes-agent runtime secrets depend on that key.
- **Disk device IDs** in `disk-config.nix` are physical identifiers tied to
  the installed drives. Do not change them.
- **`system.stateVersion = "25.05"`** must not be bumped without reading the
  NixOS release notes; it controls stateful migration behavior.

---

## Hermes Agent Configuration

The service runs natively (no container mode) as the `hermes` user.
`nixos-rebuild switch` creates the user, generates `config.yaml`, wires secrets,
and starts the gateway systemd unit.

Key option decisions:
- **`authFile` is bootstrap-only.** In managed mode, `hermes gateway install`
  and interactive auth commands are blocked. `authFile` is the only way to seed
  credentials on first activation. `authFileForceOverwrite = false` (the default)
  means the sops-stored token seeds `auth.json` once and is never applied again;
  runtime token refreshes made by hermes persist on the ZFS dataset across all
  subsequent rebuilds. The token in sops goes stale but is never re-applied — this
  is intentional. Providers can be swapped or run concurrently; each has its own
  sops binding (`anthropic_auth_json`, `codex_auth_json`).
- **Re-auth procedure:** obtain fresh tokens, update the plaintext in `.secrets/hermes-secrets.yaml`,
  re-encrypt, set `authFileForceOverwrite = true` in `hermes-agent.nix`, rebuild,
  then revert `authFileForceOverwrite` to false and rebuild again.
- `environmentFiles`: points at the `hermes-env` sops secret, a `KEY=value` env
  file merged into `$HERMES_HOME/.env` at activation.
  Current keys: `ELEVENLABS_API_KEY`, `DISCORD_BOT_TOKEN`.
- `settings.tts.elevenlabs.voice_id`: not secret — a public ElevenLabs voice
  identifier. Fill in from elevenlabs.io/app → Voices → copy voice ID.
- `HERMES_HOME` and `HERMES_MANAGED` are **owned by the module**.
  `addToSystemPackages = true` sets `HERMES_HOME` system-wide.
  `HERMES_MANAGED=true` is set by the systemd unit. Do not redeclare them in
  `environment.sessionVariables`.

Diagnostic commands:

```bash
systemctl status hermes-agent
journalctl -u hermes-agent -f
sudo -u hermes cat /var/lib/hermes/.hermes/.env   # verify secrets loaded
hermes version                                     # confirms CLI shares state
```

---

## Discord Integration Reference

Sourced from hermes-agent source + DeepWiki. Do not re-research these.

### Developer Portal Setup

1. Create application at discord.com/developers
2. Bot → Reset Token → copy as `DISCORD_BOT_TOKEN`
3. Bot → Privileged Gateway Intents → enable **all three**:
   - Message Content Intent (read message text — without this, bot is blind)
   - Server Members Intent (voice SSRC→user mapping, username allowlists)
   - Presence Intent (voice channel user detection)
4. OAuth2 → URL Generator → Integration Type: **Guild Install**
5. Scopes: check `bot` AND `applications.commands` (`applications.commands` is a scope,
   not a bot permission — it authorises the bot to register slash commands like `/voice join`)
6. Bot Permissions: enter integer `70680166124608`

### Bot Permissions (integer 70680166124608)

| Permission | Purpose |
|---|---|
| View Channels | Fundamental |
| Send Messages | Respond in channels |
| Send Messages in Threads | Threaded conversations |
| Create Public Threads | `DISCORD_AUTO_THREAD` — isolate each @mention in a thread |
| Embed Links | Rich URL previews |
| Attach Files | Code, documents, ElevenLabs voice bubbles |
| Read Message History | Conversation context |
| Add Reactions | Processing/status indicators |
| Connect | Join voice channels |
| Speak | Stream ElevenLabs audio in voice channel |
| Use Voice Activity | Detect when users are speaking |
| Use Slash Commands | `/voice join`, `/voice leave`, other slash commands |
| Send Voice Messages | ElevenLabs voice bubble delivery in text channels |

"Send TTS Messages" is Discord's own built-in synthesizer — not ElevenLabs.
Hermes does not use it. Do not grant it.

ElevenLabs audio delivery:
- Bot in voice channel → streams live audio into the channel
- Bot not in voice channel → sends as native voice bubble (Opus/OGG); falls back
  to file attachment if the voice bubble API fails

### Environment Variables (Discord)

All go in `hermes-env` secret (merged to `$HERMES_HOME/.env`).

| Variable | Required | Description |
|---|---|---|
| `DISCORD_BOT_TOKEN` | Yes | Bot token from Developer Portal |
| `DISCORD_ALLOWED_USERS` | **Yes** | Comma-separated user IDs; bot denies everyone without this |
| `DISCORD_HOME_CHANNEL` | Recommended | Channel ID for proactive output (cron, reminders) |
| `DISCORD_HOME_CHANNEL_NAME` | No | Display name for home channel in logs |
| `DISCORD_REQUIRE_MENTION` | No | Default `true` — only respond when @mentioned in servers |
| `DISCORD_FREE_RESPONSE_CHANNELS` | No | Channel IDs where mention is not required |
| `DISCORD_AUTO_THREAD` | No | Auto-create thread per @mention to isolate conversations |
| `DISCORD_REACTIONS` | No | Emoji reactions on messages during processing |
| `DISCORD_IGNORED_CHANNELS` | No | Channel IDs where bot never responds |
| `DISCORD_NO_THREAD_CHANNELS` | No | Channel IDs where auto-threading is suppressed |
| `DISCORD_REPLY_TO_MODE` | No | `off` / `first` (default) / `all` |
| `DISCORD_IGNORE_NO_MENTION` | No | Silent if message mentions others but not the bot |
| `DISCORD_ALLOW_BOTS` | No | Whether to process messages from other bots |

### Key Operational Notes

- `DISCORD_ALLOWED_USERS` is mandatory in practice. Without it the gateway
  receives all server events but rejects every interaction.
- The 1000-requests-per-day pattern with zero user activity is caused by all three
  Privileged Intents enabled without `DISCORD_ALLOWED_USERS` set — the bot receives
  a constant stream of presence/member events and processes each one.
- DMs work without channel configuration; set Bot → Allow DMs in Developer Portal.

---

## Hermes Environment Variables Reference

Keys for `hermes-env` sops secret (`$HERMES_HOME/.env`). Only list what is
configured in this deployment; full list at hermes-agent docs.

### Active

| Variable | Secret | Purpose |
|---|---|---|
| `ELEVENLABS_API_KEY` | Yes | TTS audio generation |
| `DISCORD_BOT_TOKEN` | Yes | Discord gateway connection |
| `DISCORD_ALLOWED_USERS` | No | Your Discord user ID(s) |
| `DISCORD_HOME_CHANNEL` | No | Channel ID for proactive messages |

### Provider Keys (add as needed)

| Variable | Provider |
|---|---|
| `ANTHROPIC_API_KEY` / `ANTHROPIC_TOKEN` | Anthropic direct API (OAuth token lives on dataset, not in sops) |
| `OPENROUTER_API_KEY` | OpenRouter (routes to any model) |
| `OPENAI_API_KEY` | OpenAI direct |
| `GROQ_API_KEY` | Groq Whisper STT |
| `TAVILY_API_KEY` / `EXA_API_KEY` | Web search tooling |
| `FAL_KEY` | Image generation |

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

The host IP is static and enforced at the gateway. If it changes, update your
SSH config; the NixOS configuration itself uses hostnames, not IPs.

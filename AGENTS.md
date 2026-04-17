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

**All flake inputs use FlakeHub URLs.** `NixOS/nixpkgs/0` is FlakeHub's semver
alias for nixpkgs unstable (`0` = pre-1.0 channel). Do not switch individual
inputs back to raw GitHub URLs — FlakeHub Cache works best when all inputs are
FlakeHub-sourced.

### `hosts/hermes/default.nix`

Host entry point. Contains machine-specific identity constants (`hostName`,
`hostId`, `stateVersion`, `hostPlatform`) and the import list. Nothing else.
These constants must never be extracted into shared modules.

### `hosts/hermes/hardware.nix`

Everything tied to physical hardware: initrd modules, kernel params, filesystem
mounts, bootloader, and GPU packages.

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

At install time the same file is also consumed by
`nix run github:nix-community/disko/latest -- --mode disko` to partition and
format. After first install, the partition/pool sections are effectively
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

### First Install (Live CD)

Place the age private key on the live environment first — sops-nix needs it to
decrypt all runtime secrets after install:

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
# according to the mountpoint attributes.
nix run github:nix-community/disko/latest -- --mode disko hosts/hermes/disk-config.nix

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
                                    (remote unlock via initrd SSH)
```

The host IP is static and enforced at the gateway. If it changes, update your
SSH config; the NixOS configuration itself uses hostnames, not IPs.

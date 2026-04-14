# AGENTS.md — Working Context for AI Agents

This file is the authoritative guide for AI agents (Claude, Codex, etc.)
working on this repository. Read it before touching any file.

---

## Project in One Sentence

A fully declarative NixOS flake configuration for a bare-metal AI agent host
running `hermes-agent` (NousResearch) as a personal, always-on assistant.

---

## Repository Layout

```
nixos-hermes/
├── flake.nix                            # flake inputs/outputs, host definition
├── .github/workflows/nix-ci.yml         # CI: nix flake check on push to main
├── .sops.yaml                           # sops encryption policy (age)
├── .secrets/                            # GITIGNORED — plaintext secrets, local only
│   └── hermes-secrets.yaml            # never commit; encrypt before use
├── hosts/
│   └── hermes/
│       ├── default.nix                # host entry: identity constants + imports
│       ├── hardware.nix               # boot, initrd, filesystems, kernel, GPU
│       ├── sops.nix                   # sops-nix secret bindings (host-specific)
│       ├── disk-config.nix            # disko layout (install-time, not imported)
│       └── secrets/                   # committed SOPS-encrypted files
└── modules/
    ├── system.nix                     # locale, tz, networking, packages, sudo
    ├── hermes-agent.nix               # hermes service declaration
    └── users.nix                      # immutable user + SSH key declarations
```

---

## Technology Stack

| Layer | Tool |
|-------|------|
| OS | NixOS (nixpkgs unstable via FlakeHub `NixOS/nixpkgs/0`) |
| Nix runtime | Determinate Nix (via `determinate` flake input) |
| Secret management | sops-nix + age |
| Storage | ZFS (`rpool`, mirror, encrypted) |
| Boot | systemd-boot, dual ESP |
| Agent service | `hermes-agent.nixosModules.default` |
| CI | GitHub Actions + DeterminateSystems stack |

---

## Known Bugs (Fix Before First Build)

The following defects existed in the initial state and have since been resolved.
This section is retained as reference for anyone bootstrapping from the git
history or reviewing the commit that introduced the fixes.

1. **`lib` not in scope** — `configuration.nix` used `lib.mkDefault` without
   `lib` in its module args. Fixed by adding `lib` to the function head.

2. **Wrong option name** — `networking.firewall.enabled` does not exist in
   NixOS. Corrected to `networking.firewall.enable`.

3. **Missing root filesystem mount** — `hardware-configuration.nix` had no
   `fileSystems."/"` entry for `rpool/root/nixos`. Added.

4. **`sops.nix` not imported** — the file existed but was never listed in
   `configuration.nix` imports, so no secrets would be decrypted at activation.
   Fixed by adding `./sops.nix` to the imports list.

5. **`openssh.hostKeys` missing `type`** — the entry lacked `type = "ed25519"`,
   causing NixOS to default to RSA and mishandle the key path. Fixed.

6. **Sudo gap** — `admin` has `wheel` but no password; without
   `security.sudo.wheelNeedsPassword = false`, sudo would prompt and hang.
   Fixed.
---

## Coding Conventions

### Nix style
- Module function heads use named args: `{ config, pkgs, lib, ... }:`
- One logical concern per file; do not conflate hardware and service config.
- Prefer `lib.mkDefault` only at genuine override boundaries; omit where the
  value is unconditional.
- Comments explain *why*, not *what* the code already says.

### Secrets
- **Never commit plaintext secrets.** `.secrets/` is gitignored; it exists
  only for local templating.
- The committed encrypted files live under `hosts/hermes/secrets/` with `.enc`
  suffixes (e.g., `hermes-secrets.yaml.enc`).
- The sops age key is `/etc/secrets/age.key` on the host. The corresponding
  public key is registered in `.sops.yaml`. Do not change the public key in
  `.sops.yaml` without re-encrypting every secret file.
- `.secrets/hermes-secrets.yaml` is the plaintext template (gitignored). Workflow:
  edit locally → `sops --encrypt .secrets/hermes-secrets.yaml > hosts/hermes/secrets/hermes-secrets.yaml.enc`
  → commit the `.enc` file → never commit the plaintext.
- When adding a new secret key: add it to `.secrets/hermes-secrets.yaml`, add the
  `sops.secrets.<name>` binding in `hosts/hermes/sops.nix`, then re-encrypt.

### Users
- `users.mutableUsers = false` — the NixOS activation will reject any user
  state not described in `users.nix`. Do not add users imperatively on the host.
- Authentication is SSH key only. Do not add password hashes unless explicitly
  requested.
- `admin` has `wheel` and should have `security.sudo.wheelNeedsPassword = false`
  set (or equivalent) since there is no password configured.

### Git hygiene
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
mounts, bootloader, GPU packages, initrd SSH server for remote ZFS unlock.

### `hosts/hermes/disk-config.nix`
Declarative disk layout consumed by disko at install time. Describes GPT
partitions and the ZFS pool/dataset structure. After first install this file is
reference documentation — changing it does not reformat disks.

### `hosts/hermes/sops.nix`
Maps SOPS-encrypted files to runtime paths. Lives alongside `secrets/` so that
`./secrets/...` paths resolve correctly. The age key path (`/etc/secrets/age.key`)
must not change without updating this file.

### `modules/system.nix`
Base system settings: locale, timezone, networking, openssh, sudo, packages,
and session variables. No host-specific values.

### `modules/hermes-agent.nix`
The hermes-agent service declaration. All `services.hermes-agent.*` options
live here. Secrets are referenced by name from the sops bindings.

### `modules/users.nix`
Immutable user definitions. The only place user accounts and authorized SSH
keys should appear. Lives in `modules/` because it is portable across hosts.
---

## Testing and Validation

### Local check (no host needed)
```bash
nix flake check
```

### Dry-run build (evaluates but does not activate)
```bash
nixos-rebuild dry-build --flake .#nixos-hermes
```

### First install (live CD)
The `determinate.nixosModules.default` module installs Determinate Nix from
FlakeHub. On first install, pass extra substituter flags so Nix doesn't have to
build it from source:
```bash
nixos-install --flake github:nehpz/nixos-hermes#nixos-hermes \
  --option extra-substituters https://install.determinate.systems \
  --option extra-trusted-public-keys 'cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM='
```
These flags are only required for the initial install. Once Determinate Nix
v3.6.0 or later is running on the host, subsequent `nixos-rebuild` runs need no
extra options.

### Apply to host
```bash
# Build and activate on the host directly:
ssh admin@nixos-hermes 'sudo nixos-rebuild switch --flake github:nehpz/nixos-hermes#nixos-hermes'

# Or push from local checkout (builds on the host, required — see hardware.nix):
nixos-rebuild switch --flake .#nixos-hermes \
  --target-host admin@nixos-hermes \
  --build-host  admin@nixos-hermes \
  --use-remote-sudo
```

CI runs `nix flake check` automatically on push to `main`. There is no
automated deploy; all applies are manual.

---

## Invariants — Do Not Break

- **Pool name `rpool` is fixed.** The ZFS hostId (`52dd4e5a`) ties the pool to
  this host. Changing either requires pool export/import.
- **The age public key in `.sops.yaml`** must match the private key at
  `/etc/secrets/age.key` on the host. They are a matched pair generated once.
- **The initrd SSH host key** (`/etc/ssh/ssh_host_ed25519_key`) is injected
  into the initrd at build time via `boot.initrd.secrets`. The same key is
  managed by SOPS for the main-stage SSH server. Replacing it requires
  re-encrypting `hosts/hermes/secrets/ssh_host_ed25519_key.enc` and updating known-hosts
  on every client.
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
- **OAuth auth tokens are not managed by sops.** Tokens for all providers
  (`auth.json`) persist on the ZFS dataset (`rpool/data/hermes` →
  `/var/lib/hermes/.hermes/`) and are managed entirely at runtime by the
  hermes-agent process. Providers can be swapped or used concurrently; their
  tokens refresh independently. Baking them into sops would treat ephemeral
  credentials as static secrets and cause stale-token failures after expiry.
- **First-boot auth bootstrap:** after `nixos-install` and first login, run
  `hermes auth login` for each provider before starting the service, or
  manually place a valid `auth.json` at `/var/lib/hermes/.hermes/auth.json`.
  The dataset persists across all subsequent rebuilds.
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

```
GitHub (nehpz/nixos-hermes)
    │
    ├─ push to main → CI: nix flake check (validate only)
    │
    └─ manual: nixos-rebuild switch → nixos-hermes
                                           │
                                    ZFS mirror rpool
                                    (remote unlock via initrd SSH)
```

The host IP is static and enforced at the gateway. If it changes, update your
SSH config; the NixOS configuration itself uses hostnames, not IPs.

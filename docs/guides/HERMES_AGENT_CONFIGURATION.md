# Hermes Agent Configuration

The service runs natively (no container mode) as the `hermes` user. `nixos-rebuild switch` creates the user, generates `config.yaml`, wires secrets, and starts the gateway `systemd` unit.

## Key `options` configuration

### `environmentFiles`

- Points at the `hermes-env` sops secret, a `KEY=value` env file merged into `$HERMES_HOME/.env` at activation
- Current keys: `ELEVENLABS_API_KEY`, `DISCORD_BOT_TOKEN`

### `settings.tts.elevenlabs.voice_id`

- Not secret — a public ElevenLabs voice identifier
- Fill in from `elevenlabs.io/app` → Voices → copy voice ID

### `HERMES_HOME` / `HERMES_MANAGED`

- Both are owned by the `hermes-agent.nix` module
  - `addToSystemPackages = true` sets `HERMES_HOME` system-wide
  - `HERMES_MANAGED=true` is set by the `systemd` unit
- Do not redeclare them in `environment.sessionVariables`

---

## Diagnostic commands

```bash
systemctl status hermes-agent
journalctl -u hermes-agent -f
sudo -u hermes cat /var/lib/hermes/.hermes/.env    # verify secrets loaded
hermes version                                     # confirms CLI shares state
```

---

## Discord Integration Reference

Sourced from hermes-agent repository + DeepWiki on `2026-04-14`.

### Developer Portal Setup

1. Create a new application at discord.com/developers
2. Bot → Reset Token → copy as `DISCORD_BOT_TOKEN`
3. Bot → Privileged Gateway Intents → enable **all three**:
   - Message Content Intent (read message text — without this, bot is blind)
   - Server Members Intent (voice SSRC→user mapping, username allowlists)
   - Presence Intent (voice channel user detection)
4. OAuth2 → URL Generator → Integration Type: **Guild Install**
5. Scopes: check `bot` AND `applications.commands` (`applications.commands` is a scope,
   not a bot permission — it authorizes the bot to register slash commands like `/voice join`)
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

"Send TTS Messages" is Discord's own built-in synthesizer — not ElevenLabs. Hermes does not use it. Do not grant it.

ElevenLabs audio delivery:
- Bot in voice channel → streams live audio into the channel
- Bot not in voice channel → sends as native voice bubble (Opus/OGG); falls back to file attachment if the voice bubble API fails

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

- `DISCORD_ALLOWED_USERS` is mandatory in practice. Without it the gateway receives all server events but rejects every interaction.
- The 1000-requests-per-day pattern with zero user activity is caused by all three Privileged Intents enabled without `DISCORD_ALLOWED_USERS` set — the bot receives a constant stream of presence/member events and processes each one.
- DMs work without channel configuration; set Bot → Allow DMs in Developer Portal.

---

## Hermes Environment Variables Reference

Keys for `hermes-env` sops secret (`$HERMES_HOME/.env`). Only list what is configured in this deployment; a full list at hermes-agent docs.

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

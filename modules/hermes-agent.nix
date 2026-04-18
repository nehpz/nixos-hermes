{
  config,
  pkgs,
  lib,
  ...
}:

{
  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;

    # Seeds auth.json on first activation only (authFileForceOverwrite defaults
    # to false). Runtime token refreshes survive all subsequent rebuilds.
    # Active provider is anthropic; codex available for subagent delegation.
    authFile = config.sops.secrets.anthropic_auth_json.path;

    # Packages required by enabled toolsets.
    # playwright-driver.browsers: NixOS-wrapped browser binaries for the browser toolset.
    # ffmpeg: audio processing for ElevenLabs TTS voice bubble delivery.
    # ripgrep: fast search used by file and terminal toolsets.
    # libopus: shared library for Discord voice channel encode/decode. discord.py loads
    #   it via ctypes at runtime; ctypes.util.find_library fails on NixOS (no ldconfig),
    #   so the library path is injected via LD_LIBRARY_PATH in the systemd environment below.
    extraPackages = with pkgs; [
      playwright-driver.browsers
      ffmpeg
      ripgrep
      libopus
    ];

    # Non-secret environment variables injected into the service.
    # PLAYWRIGHT_BROWSERS_PATH tells hermes's internal Playwright where NixOS
    # placed the browser binaries (standard PATH lookup does not work for Playwright).
    # DISCORD_ALLOWED_USERS: user allowlisting is env-only; settings.discord has no
    # equivalent key — placing it here keeps it out of the secret bundle.
    environment = {
      PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
      DISCORD_ALLOWED_USERS = "185292472836947968";
    };

    # API keys merged into $HERMES_HOME/.env at activation.
    # Current keys: ELEVENLABS_API_KEY, DISCORD_BOT_TOKEN
    # DISCORD_ALLOWED_USERS is in environment above (non-secret).
    environmentFiles = [ config.sops.secrets."hermes-env".path ];

    settings = {
      model = {
        provider = "anthropic";
        # Explicit base_url overrides any OpenRouter URL that hermes may have written
        # to config.yaml on first boot. Without this, the disk value survives the
        # deep-merge and requests would be routed through OpenRouter regardless of provider.
        base_url = "https://api.anthropic.com";
        default = "claude-sonnet-4-6";
      };

      # Capabilities the agent may invoke.
      toolsets = [
        "hermes-cli" # Full toolset — all 36 tools including clarify. The default for interactive CLI sessions
      ];

      tts = {
        provider = "elevenlabs";
        elevenlabs = {
          voice_id = "cgSgspJ2msm6clMCkdW9";
          model_id = "eleven_flash_v2_5";
        };
      };

      # Discord operational behaviour — not secrets; live here, not in hermes-env.
      # DISCORD_BOT_TOKEN remains in the hermes-env sops secret.
      # DISCORD_ALLOWED_USERS is wired via environment above (config.yaml has no allowed_users key).
      discord = {
        require_mention = true; # Respond only when @mentioned
        auto_thread = true; # Isolate each conversation in a thread
        reactions = true; # Emoji reactions for processing state
        allowed_channels = [
          # Restrict to specific channel IDs; empty = all
          "1493930581090762833" # hermes-yui (text)
          "1493930714687869028" # hermes-yui-voice (voice)
        ];
        free_response_channels = [ ]; # Channels that respond without @mention
        home_channel = "1493934973009526884"; # hermes-home (text)
      };

      # One session per user per channel — prevents session bleed in shared servers.
      group_sessions_per_user = true;

      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
      };

      # Compress context at 50% of the model's context window.
      compression = {
        enabled = true;
        threshold = 0.50;
      };

      agent = {
        max_turns = 50; # Hard ceiling on turns per conversation
      };

      checkpoints = {
        enabled = true;
        max_snapshots = 50;
      };
    };
  };

  # LD_LIBRARY_PATH injected into the systemd unit directly (not .env) so ctypes
  # can find libopus when discord.py attempts discord.opus.load_opus() at import time,
  # which happens before Python reads $HERMES_HOME/.env via load_hermes_dotenv().
  systemd.services.hermes-agent.environment = {
    LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.libopus ];
  };

  # Provision SOUL.md to $HERMES_HOME on first boot only. Subsequent rebuilds
  # leave the file untouched so the agent can evolve it freely at runtime.
  # To canonicalize an evolved version: update modules/soul.md, delete the file
  # on the host, then rebuild — the guard will re-provision from the new source.
  system.activationScripts.hermes-soul-md = lib.stringAfter [ "hermes-agent-setup" ] ''
    soul_path=${config.services.hermes-agent.stateDir}/.hermes/SOUL.md
    if [ ! -f "$soul_path" ]; then
      install \
        -o ${config.services.hermes-agent.user} \
        -g ${config.services.hermes-agent.group} \
        -m 0640 \
        ${./soul.md} "$soul_path"
    fi
  '';
}

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

    # Seeds auth.json on first activation only.
    # Runtime token refreshes survive all subsequent rebuilds.
    # Active provider is anthropic.
    authFile = config.sops.secrets.auth_json.path;
    authFileForceOverwrite = false;

    # Packages required by enabled toolsets.
    # playwright-driver.browsers: NixOS-wrapped browser binaries for the browser toolset.
    # ffmpeg: audio processing for ElevenLabs TTS voice bubble delivery.
    # ripgrep: fast search used by file and terminal toolsets.
    # libopus: pins the store path referenced by the opus ctypes shim (see modules/packages.nix).
    extraPackages = with pkgs; [
      playwright-driver.browsers
      ffmpeg
      ripgrep
      libopus
      codex
      pkgs."agent-browser"
    ];

    # Non-secret environment variables injected into the service.
    # PLAYWRIGHT_BROWSERS_PATH tells hermes's internal Playwright where NixOS
    # placed the browser binaries (standard PATH lookup does not work for Playwright).
    # DISCORD_ALLOWED_USERS: user allowlisting is env-only; settings.discord has no
    # equivalent key — placing it here keeps it out of the secret bundle.
    # DISCORD_HOME_CHANNEL: 0.10.0 gateway reads this env var to determine the home
    # channel; settings.discord.home_channel populates config.yaml but is not consulted
    # by the runtime check.
    environment = {
      PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
      DISCORD_ALLOWED_USERS = "185292472836947968";
      DISCORD_HOME_CHANNEL = "1493934973009526884";
    };

    # API keys merged into $HERMES_HOME/.env at activation.
    # Current keys: ELEVENLABS_API_KEY, DISCORD_BOT_TOKEN
    # DISCORD_ALLOWED_USERS is in environment above (non-secret).
    environmentFiles = [ config.sops.secrets."hermes-env".path ];

    settings = {
      model = {
        # Explicit provider overrides any OpenRouter default provider.
        provider = "anthropic";
        default = "claude-sonnet-4-6";
      };
      auxiliary = {
        vision = {
          provider = "google-gemini-cli";
          model = "gemini-3.1-pro-preview";
        };
        web_extract = {
          provider = "google-gemini-cli";
          model = "gemini-3-flash-preview";
        };
      };
      # Replaces the deprecated MESSAGING_CWD environment variable.
      # The upstream module still injects MESSAGING_CWD into the service;
      # UnsetEnvironment below removes it so hermes reads only config.yaml.
      terminal = {
        cwd = config.services.hermes-agent.workingDirectory;
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
    mcpServers = {
      nixos = {
        command = "uvx";
        args = [ "mcp-nixos" ];
      };
      deepwiki = {
        url = "https://mcp.deepwiki.com/mcp";
        registry = "io.windsurf/deepwiki";
        timeout = 180;
      };
    };
  };

  # MESSAGING_CWD is deprecated in 0.10.0 in favour of terminal.cwd in config.yaml.
  # The upstream nixosModules.nix still sets it unconditionally; UnsetEnvironment
  # removes it from the service environment so hermes sees only the config.yaml value.
  systemd.services.hermes-agent.serviceConfig.UnsetEnvironment = [ "MESSAGING_CWD" ];

  # opusCtypesShim patches ctypes.util.find_library("opus") at interpreter startup.
  # sitecustomize.py is imported by site.py before any user code; PYTHONPATH prepends
  # our directory so it takes precedence over any existing sitecustomize in site-packages.
  systemd.services.hermes-agent.environment = {
    PYTHONPATH = toString pkgs.opusCtypesShim;
  };

}

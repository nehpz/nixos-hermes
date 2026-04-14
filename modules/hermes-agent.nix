{ config, ... }:

{
  services.hermes-agent = {
    enable              = true;
    addToSystemPackages = true;

    # API keys merged into $HERMES_HOME/.env at activation.
    # Current keys: ELEVENLABS_API_KEY, DISCORD_BOT_TOKEN
    # Non-secret Discord behaviour belongs in settings.discord below, not here.
    environmentFiles = [ config.sops.secrets."hermes-env".path ];

    # Agent identity and user profile written to $HERMES_HOME on activation.
    # Editing here and rebuilding updates the agent without a manual file edit.
    # Run `hermes soul` after first boot to see the upstream default template.
    documents = {
      "SOUL.md" = ''
        # Hermes

        You are Hermes, a personal AI assistant running on nixos-hermes.
        You are always-on, proactive, and operate as a trusted technical companion.

        <!-- Replace with actual SOUL.md content. -->
      '';
      # "USER.md" = ./user.md;  # Uncomment and populate for user-profile personalisation.
    };

    settings = {
      model = {
        provider = "anthropic";
        default  = "claude-sonnet-4-6";
      };

      # Capabilities the agent may invoke.
      toolsets = [
        "terminal"       # Shell commands on the host
        "file"           # File read/write
        "web"            # Web search and content extraction
        "browser"        # Browser automation (Playwright)
        "vision"         # Image analysis
        "code_execution" # Sandboxed Python execution
        "tts"            # Text-to-speech (wired to ElevenLabs below)
        "skills"         # Custom skill loading
        "todo"           # Task management
        "cronjob"        # Scheduled jobs
        "messaging"      # Platform messaging tools (Discord)
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
      discord = {
        require_mention          = true;  # Respond only when @mentioned
        auto_thread              = true;  # Isolate each conversation in a thread
        reactions                = true;  # Emoji reactions for processing state
        # allowed_channels       = [];    # Restrict to specific channel IDs; empty = all
        # free_response_channels = [];    # Channels that respond without @mention
      };

      # One session per user per channel — prevents session bleed in shared servers.
      group_sessions_per_user = true;

      memory = {
        memory_enabled       = true;
        user_profile_enabled = true;
      };

      # Compress context at 50% of the model's context window.
      compression = {
        enabled   = true;
        threshold = 0.50;
      };

      agent = {
        max_turns = 50;  # Hard ceiling on turns per conversation
      };

      checkpoints = {
        enabled       = true;
        max_snapshots = 50;
      };
    };
  };
}

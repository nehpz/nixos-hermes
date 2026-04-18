{
  config,
  pkgs,
  lib,
  ...
}:

# nixpkgs patches CPython with no-ldconfig.patch — ctypes.util._findSoname_ldconfig
# unconditionally returns None. LD_LIBRARY_PATH and ldconfig cache approaches are
# both dead. Inject a sitecustomize.py via PYTHONPATH that patches find_library("opus")
# to return the Nix store path directly before any user code runs.
let
  opusCtypesShim = pkgs.writeTextDir "sitecustomize.py" ''
    import ctypes.util as _cu

    _OPUS_PATH = "${pkgs.libopus}/lib/libopus.so.0"
    _orig = _cu.find_library

    def find_library(name, *args, **kwargs):
        if name == "opus":
            return _OPUS_PATH
        return _orig(name, *args, **kwargs)

    _cu.find_library = find_library
  '';
in
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
    # libopus: pins the store path referenced by opusCtypesShim above.
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
        provider = "anthropic";
        # Explicit base_url overrides any OpenRouter URL that hermes may have written
        # to config.yaml on first boot. Without this, the disk value survives the
        # deep-merge and requests would be routed through OpenRouter regardless of provider.
        base_url = "https://api.anthropic.com";
        default = "claude-sonnet-4-6";
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
  };

  # opusCtypesShim patches ctypes.util.find_library("opus") at interpreter startup.
  # sitecustomize.py is imported by site.py before any user code; PYTHONPATH prepends
  # our directory so it takes precedence over any existing sitecustomize in site-packages.
  systemd.services.hermes-agent.environment = {
    PYTHONPATH = toString opusCtypesShim;
  };

  # MESSAGING_CWD is deprecated in 0.10.0 in favour of terminal.cwd in config.yaml.
  # The upstream nixosModules.nix still sets it unconditionally; UnsetEnvironment
  # removes it from the service environment so hermes sees only the config.yaml value.
  systemd.services.hermes-agent.serviceConfig.UnsetEnvironment = [ "MESSAGING_CWD" ];

  # Provision SOUL.md to $HERMES_HOME on first boot only. Subsequent rebuilds
  # leave the file untouched so the agent can evolve it freely at runtime.
  # To canonicalize an evolved version: update hosts/hermes/secrets/soul.md
  # (re-encrypt with sops), delete the file on the host, then rebuild.
  system.activationScripts.hermes-soul-md =
    lib.stringAfter
      [
        "hermes-agent-setup"
        "setupSecrets"
      ]
      ''
        soul_path=${config.services.hermes-agent.stateDir}/.hermes/SOUL.md
        if [ ! -f "$soul_path" ]; then
          install \
            -o ${config.services.hermes-agent.user} \
            -g ${config.services.hermes-agent.group} \
            -m 0640 \
            ${config.sops.secrets.hermes-soul-md.path} "$soul_path"
        fi
      '';

  # Provision Claude Code credentials to the hermes user's home on first boot.
  # hermes reads ~/.claude/.credentials.json (Claude Code format) via
  # read_claude_code_credentials() and auto-refreshes the access token using
  # the refresh token. Provision-once so hermes can overwrite the file with
  # fresh tokens; subsequent rebuilds leave it untouched.
  system.activationScripts.hermes-claude-credentials =
    lib.stringAfter
      [
        "hermes-agent-setup"
        "setupSecrets"
      ]
      ''
        creds_dir=${config.services.hermes-agent.stateDir}/.claude
        creds_path=$creds_dir/.credentials.json
        if [ ! -f "$creds_path" ]; then
          mkdir -p "$creds_dir"
          chown ${config.services.hermes-agent.user}:${config.services.hermes-agent.group} "$creds_dir"
          install \
            -o ${config.services.hermes-agent.user} \
            -g ${config.services.hermes-agent.group} \
            -m 0600 \
            ${config.sops.secrets.hermes-claude-credentials.path} "$creds_path"
        fi
      '';
}

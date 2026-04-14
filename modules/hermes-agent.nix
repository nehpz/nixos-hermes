{ config, ... }:

{
  services.hermes-agent = {
    enable              = true;
    addToSystemPackages = true;

    # OAuth credentials seed for the Anthropic provider (auth.json format).
    # Copied on first deploy; preserved on subsequent rebuilds so runtime token
    # refreshes are not overwritten. Set authFileForceOverwrite = true to reseed.
    authFile = config.sops.secrets.anthropic_auth_json.path;

    # API keys merged into $HERMES_HOME/.env at activation.
    # Keys expected: ELEVENLABS_API_KEY, DISCORD_BOT_TOKEN
    environmentFiles = [ config.sops.secrets."hermes-env".path ];

    settings = {
      model = {
        provider = "anthropic";
        default  = "claude-sonnet-4-6";
      };
      tts = {
        provider = "elevenlabs";
        elevenlabs = {
          voice_id = "cgSgspJ2msm6clMCkdW9";
          model_id = "eleven_flash_v2_5";
        };
      };
    };
  };
}
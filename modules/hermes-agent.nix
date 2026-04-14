{ config, ... }:

{
  services.hermes-agent = {
    enable              = true;
    addToSystemPackages = true;


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
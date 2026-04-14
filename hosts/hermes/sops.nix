{ config, ... }:

{
  sops.defaultSopsFile = ./secrets/hermes-secrets.yaml.enc;
  sops.age.keyFile = "/etc/secrets/age.key";

  sops.secrets = {
    # Stable SSH host key — injected into /etc/ssh so both initrd and main-stage
    # SSH present the same host identity across rebuilds.
    ssh_host_ed25519_key = {
      sopsFile = ./secrets/ssh_host_ed25519_key.enc;
      format   = "binary";
      owner    = "root";
      mode     = "0600";
      path     = "/etc/ssh/ssh_host_ed25519_key";
    };

    # Combined env file for hermes-agent: ELEVENLABS_API_KEY, DISCORD_BOT_TOKEN, etc.
    # Value is a newline-delimited KEY=value file; merged into $HERMES_HOME/.env
    # at activation time by the hermes-agent module.
    "hermes-env" = {
      owner = "hermes";
      mode  = "0400";
    };

    # OAuth credentials seed for the OpenAI Codex provider (auth.json format).
    # Passed to services.hermes-agent.authFile.
    codex_auth_json = {
      owner = "hermes";
      mode  = "0400";
    };

    # OAuth credentials seed for the Anthropic provider (auth.json format).
    # Passed to services.hermes-agent.authFile.
    anthropic_auth_json = {
      owner = "hermes";
      mode  = "0400";
    };
  };
}
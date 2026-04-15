{ config, ... }:

{
  sops.defaultSopsFile = ./secrets/hermes-secrets.yaml;
  sops.age.keyFile = "/etc/secrets/age.key";

  sops.secrets = {

    # Stable SSH host key — same fingerprint survives rebuilds.
    # Pre-place at /mnt/etc/ssh/ssh_host_ed25519_key before nixos-install
    # (see First Install procedure); sops-nix maintains it on subsequent rebuilds.
    ssh_host_ed25519_key = {
      sopsFile = ./secrets/ssh_host_ed25519_key.enc;
      format = "binary";
      owner = "root";
      mode = "0600";
      path = "/etc/ssh/ssh_host_ed25519_key";
    };

    # Combined env file for hermes-agent: ELEVENLABS_API_KEY, DISCORD_BOT_TOKEN, etc.
    # Value is a newline-delimited KEY=value file; merged into $HERMES_HOME/.env
    # at activation time by the hermes-agent module.
    "hermes-env" = {
      owner = "hermes";
      mode = "0400";
    };

    # OAuth bootstrap credentials for hermes-agent providers.
    # authFileForceOverwrite = false (default) means these seed auth.json on
    # first activation only; runtime token refreshes are never overwritten.
    # To re-auth: update tokens here, set authFileForceOverwrite = true, rebuild,
    # then revert to false.
    anthropic_auth_json = {
      owner = "hermes";
      mode = "0400";
    };
    codex_auth_json = {
      owner = "hermes";
      mode = "0400";
    };
  };
}

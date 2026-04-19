{ config, ... }:

{
  sops.defaultSopsFile = ./secrets/hermes-secrets.yaml;
  sops.age.keyFile = "/etc/secrets/age.key";
  # The SSH host key is itself a sops-managed secret; using it as an age
  # identity creates a circular dependency. Use only the age key file.
  sops.age.sshKeyPaths = [ ];

  sops.secrets = {

    # Stable SSH host key — same fingerprint survives rebuilds.
    # sops-nix decrypts and places this at runtime; no pre-placement needed.
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
    auth_json = {
      owner = "hermes";
      mode = "0400";
    };

    # Agent personality — encrypted so contents remain private in the public repo.
    # Decrypted by sops-nix at activation; the hermes-soul-md script provisions
    # it to $HERMES_HOME on first boot only.
    hermes-soul-md = {
      sopsFile = ./secrets/soul.md;
      format = "binary";
      owner = "hermes";
      mode = "0440";
    };

    # Claude Code credentials for Anthropic OAuth. Seeded with the refresh token;
    # hermes auto-refreshes the access token on first use and updates the file.
    hermes-claude-credentials = {
      sopsFile = ./secrets/claude-credentials.json;
      format = "binary";
      owner = "hermes";
      mode = "0400";
    };
  };
}

{ ... }:

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

    # Combined env file for hermes-agent: ELEVENLABS_API_KEY, DISCORD_BOT_TOKEN,
    # OPENROUTER_API_KEY, LINEAR_API_KEY, etc.
    # Value is a newline-delimited KEY=value file; merged into $HERMES_HOME/.env
    # at activation time by the hermes-agent module.
    "hermes-env" = {
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

  };
}

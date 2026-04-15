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

    # ZFS pool encryption key — decrypted to /etc/secrets/zfs.key during activation.
    # boot.initrd.secrets then bakes it into the initrd so the pool unlocks at boot.
    zfs_key = {
      sopsFile = ./secrets/zfs.key.enc;
      format   = "binary";
      owner    = "root";
      mode     = "0400";
      path     = "/etc/secrets/zfs.key";
    };

    # Combined env file for hermes-agent: ELEVENLABS_API_KEY, DISCORD_BOT_TOKEN, etc.
    # Value is a newline-delimited KEY=value file; merged into $HERMES_HOME/.env
    # at activation time by the hermes-agent module.
    "hermes-env" = {
      owner = "hermes";
      mode  = "0400";
    };

    # OAuth bootstrap credentials for hermes-agent providers.
    # authFileForceOverwrite = false (default) means these seed auth.json on
    # first activation only; runtime token refreshes are never overwritten.
    # To re-auth: update tokens here, set authFileForceOverwrite = true, rebuild,
    # then revert to false.
    anthropic_auth_json = {
      owner = "hermes";
      mode  = "0400";
    };
    codex_auth_json = {
      owner = "hermes";
      mode  = "0400";
    };
  };
}
{ config, lib, ... }:

# Host-specific first-boot provisioning. Each activation script runs once;
# the guard ensures rebuilds do not clobber runtime-evolved state.
# To re-provision: delete the target file on the host, then rebuild.
{
  system.activationScripts.hermes-soul-md =
    lib.stringAfter
      [
        "hermes-agent-setup"
        "setupSecrets"
      ]
      ''
        soul_path=${config.services.hermes-agent.stateDir}/.hermes/SOUL.md
        soul_dir=$(dirname "$soul_path")
        # Create .hermes/ with hermes ownership before install so the service
        # user can write into the directory once it starts.
        if [ ! -d "$soul_dir" ]; then
          install -d \
            -o ${config.services.hermes-agent.user} \
            -g ${config.services.hermes-agent.group} \
            -m 0750 \
            "$soul_dir"
        fi
        if [ ! -f "$soul_path" ]; then
          install \
            -o ${config.services.hermes-agent.user} \
            -g ${config.services.hermes-agent.group} \
            -m 0640 \
            ${config.sops.secrets.hermes-soul-md.path} "$soul_path"
        fi
      '';

  # Write ~/.git-credentials on every activation so git push works after
  # rebuilds without manual intervention. The token lives in the hermes-env
  # sops secret and is sourced from the decrypted env file at runtime.
  # No first-boot guard — the file must be refreshed whenever the secret changes.
  system.activationScripts.hermes-git-credentials =
    lib.stringAfter
      [
        "setupSecrets"
        "users"
      ]
      ''
        creds_path=${config.services.hermes-agent.stateDir}/.git-credentials
        token=$(grep "^GITHUB_TOKEN=" ${config.sops.secrets."hermes-env".path} | cut -d= -f2 | tr -d '"')
        if [ -n "$token" ]; then
          printf 'https://yui-hermes:%s@github.com\n' "$token" > "$creds_path"
          chmod 600 "$creds_path"
          chown ${config.services.hermes-agent.user}:${config.services.hermes-agent.group} "$creds_path"
        fi
      '';
}

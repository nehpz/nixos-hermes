{ config, lib, ... }:

# Host-specific activation scripts. Two categories:
#   - One-shot provisioning: runs once on first boot; a file-existence guard
#     ensures rebuilds do not clobber runtime-evolved state. To re-provision,
#     delete the target file on the host and rebuild.
#   - Recurring refresh: runs on every activation with no guard; used for
#     credentials and other state that must stay in sync with sops secrets.
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
        token=$(grep "^GITHUB_TOKEN=" ${
          config.sops.secrets."hermes-env".path
        } | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//')
        if [ -n "$token" ]; then
          # Create with correct ownership and mode atomically before writing
          # content — avoids a race where the file is briefly world-readable.
          install -D -m 600 \
            -o ${config.services.hermes-agent.user} \
            -g ${config.services.hermes-agent.group} \
            /dev/null "$creds_path"
          printf 'https://yui-hermes:%s@github.com\n' "$token" > "$creds_path"
        else
          # Token removed from secret — revoke file so stale credentials
          # do not persist on disk.
          rm -f "$creds_path"
        fi
      '';
}

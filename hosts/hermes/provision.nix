{
  config,
  lib,
  pkgs,
  ...
}:

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

  # Write GitHub credentials on every activation so both git and gh work
  # after rebuilds without manual intervention. The token lives in the
  # hermes-env sops secret and is sourced from the decrypted env file at
  # runtime. No first-boot guard — credentials must refresh whenever the
  # secret changes.
  system.activationScripts.hermes-github-auth =
    lib.stringAfter
      [
        "hermes-agent-setup"
        "setupSecrets"
        "users"
      ]
      ''
        state_dir=${config.services.hermes-agent.stateDir}
        creds_path=$state_dir/.git-credentials
        gh_parent_dir=$state_dir/.config
        gh_config_dir=$gh_parent_dir/gh
        gh_hosts_path=$gh_config_dir/hosts.yml
        gh_config_path=$gh_config_dir/config.yml
        token=$(grep "^GITHUB_TOKEN=" ${config.sops.secrets."hermes-env".path} | cut -d= -f2-)
        # Strip surrounding double quotes using bash parameter expansion —
        # sed is not available in the activation script PATH.
        token=''${token#\"}
        token=''${token%\"}

        if [ -n "$token" ]; then
          # Create with correct ownership and mode atomically before writing
          # content — avoids a race where credentials are briefly readable by
          # another user.
          install -D -m 600 \
            -o ${config.services.hermes-agent.user} \
            -g ${config.services.hermes-agent.group} \
            /dev/null "$creds_path"
          printf 'https://yui-hermes:%s@github.com\n' "$token" > "$creds_path"

          install -d \
            -o ${config.services.hermes-agent.user} \
            -g ${config.services.hermes-agent.group} \
            -m 0700 \
            "$gh_parent_dir"
          chmod u=rwx,go=,g-s "$gh_parent_dir"

          install -d \
            -o ${config.services.hermes-agent.user} \
            -g ${config.services.hermes-agent.group} \
            -m 0700 \
            "$gh_config_dir"
          chmod u=rwx,go=,g-s "$gh_config_dir"

          install -m 600 \
            -o ${config.services.hermes-agent.user} \
            -g ${config.services.hermes-agent.group} \
            /dev/null "$gh_hosts_path"
          printf '%s\n' \
            'github.com:' \
            "    oauth_token: $token" \
            '    user: yui-hermes' \
            '    git_protocol: https' \
            > "$gh_hosts_path"

          install -m 600 \
            -o ${config.services.hermes-agent.user} \
            -g ${config.services.hermes-agent.group} \
            /dev/null "$gh_config_path"
        else
          # Token removed from secret — revoke files so stale credentials
          # do not persist on disk.
          rm -f "$creds_path" "$gh_hosts_path" "$gh_config_path"
        fi

        # Smoke-test that gh can read its configured token without requiring
        # network access. This catches malformed hosts.yml during activation.
        if [ -f "$gh_hosts_path" ]; then
          HOME=$state_dir ${pkgs.gh}/bin/gh auth token >/dev/null
        fi
      '';
}

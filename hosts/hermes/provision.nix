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
}

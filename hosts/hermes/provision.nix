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
        if [ ! -f "$soul_path" ]; then
          install -D \
            -o ${config.services.hermes-agent.user} \
            -g ${config.services.hermes-agent.group} \
            -m 0640 \
            ${config.sops.secrets.hermes-soul-md.path} "$soul_path"
        fi
      '';
}

# tests/default.nix — NixOS VM test suite
#
# Run individual tests with:
#   nix build .#checks.x86_64-linux.activation-git-credentials
#
# These tests require QEMU — they run unprivileged via nixosTest.
# Use the testing ladder in AGENTS.md to decide when to run VM tests
# vs lighter-weight checks.
{
  pkgs,
  lib,
  sops-nix,
  hermes-agent,
}:

let
  # Throwaway age key for test secrets — committed intentionally.
  # This key encrypts only dummy test values, never real secrets.
  testAgeKeyFile = ./assets/age-test-key.txt;
  testSecretsFile = ./assets/test-secrets.yaml;

  # Shared base config for tests that need the hermes-agent activation
  # scripts. Imports the real upstream module with the service enabled so
  # hermes-agent-setup runs exactly as it does on the live host. The agent
  # binary will not start (no valid config/secrets for the service) but
  # activation scripts run before systemd units and succeed independently.
  hermesBaseModule =
    { config, lib, ... }:
    {
      imports = [
        sops-nix.nixosModules.sops
        hermes-agent.nixosModules.default
      ];

      # Inject test age key via initrd — same pattern as sops-nix's own tests.
      # The key is copied to /run/age-keys.txt during early boot so sops-nix
      # can decrypt secrets during the activation phase.
      boot.initrd.postDeviceCommands = ''
        cp -r ${testAgeKeyFile} /run/age-keys.txt
        chmod 700 /run/age-keys.txt
      '';

      sops.age.keyFile = "/run/age-keys.txt";
      sops.age.sshKeyPaths = [ ];
      sops.defaultSopsFile = testSecretsFile;
      sops.secrets."hermes-env" = {
        owner = "hermes";
        mode = "0400";
      };
      sops.secrets."hermes-soul-md" = {
        owner = "hermes";
        mode = "0440";
      };

      # Minimal hermes-agent config — enough to run hermes-agent-setup
      # and hermes-git-credentials activation scripts.
      services.hermes-agent = {
        enable = true;
        # Suppress missing required options with stub values
        authFile = pkgs.writeText "test-auth.json" (
          builtins.toJSON {
            version = 1;
            providers = { };
            credential_pool = { };
          }
        );
        environmentFiles = [ config.sops.secrets."hermes-env".path ];
        settings.model = {
          default = "test-model";
          provider = "test-provider";
        };
      };

      # Required for nixosTest
      system.stateVersion = "25.11";
    };

in
{
  # Test: hermes-git-credentials activation script
  # Verifies the script correctly writes ~/.git-credentials from sops secret.
  activation-git-credentials = pkgs.testers.runNixOSTest {
    name = "activation-git-credentials";

    nodes.machine =
      { ... }:
      {
        imports = [
          hermesBaseModule
          ../hosts/hermes/provision.nix
        ];
      };

    testScript = ''
      machine.wait_for_unit("multi-user.target")

      # File must exist
      machine.succeed("test -f /var/lib/hermes/.git-credentials")

      # Mode must be 600
      machine.succeed(
          "stat -c%a /var/lib/hermes/.git-credentials | grep -qx 600"
      )

      # Owner must be hermes
      machine.succeed(
          "stat -c%U /var/lib/hermes/.git-credentials | grep -qx hermes"
      )

      # Content must be correct — token contains = signs (tests cut -d= -f2- fix)
      machine.succeed(
          "grep -qF 'https://yui-hermes:ghp_AAAAAAAAAAAAAAAA1234567890==test@github.com'"
          " /var/lib/hermes/.git-credentials"
      )
    '';
  };
}

# Plan: NixOS Test Infrastructure

**Date:** 2026-04-20
**Status:** Implemented — PR #12

---

## Goal

Add a `nixosTest`-based testing infrastructure to the flake so activation
scripts and NixOS module behaviour can be verified in an isolated VM before
opening a PR. Catches issues like the `sed`-not-in-PATH failure before they
reach the host.

---

## Current State

- No tests exist in the repo
- Activation script bugs have been caught only after `nixos-rebuild switch`
  on the live host
- sops-nix already has a well-established pattern for testing with secrets
  in NixOS VMs (throwaway age key + pre-encrypted dummy secrets)
- The flake already has a `checks` output (currently only `pre-commit-check`)

---

## Approach

Use `pkgs.testers.runNixOSTest` (the modern wrapper around `nixos/lib/testing-python.nix`)
with a throwaway age key and dummy secrets. Tests live under `tests/` and are
wired into `checks` in `flake.nix` alongside `pre-commit-check`.

The test age key and dummy secret file are committed to the repo — they are
**not sensitive**: the key is throwaway and the secrets are dummy values only
used in tests.

---

## Repository Layout Changes

```
tests/
├── assets/
│   ├── age-test-key.txt          # throwaway age private key (committed, not sensitive)
│   └── test-secrets.yaml         # sops-encrypted dummy secrets (encrypted with age-test-key)
└── default.nix                   # test suite entry point
```

---

## Asset Generation (one-time, manual steps)

These are done once during implementation:

```bash
# 1. Generate throwaway age key
nix run nixpkgs#age -- -keygen -o tests/assets/age-test-key.txt

# 2. Extract public key
AGE_PUBKEY=$(nix run nixpkgs#age -- -keygen -y tests/assets/age-test-key.txt)
# Or: grep "public key" tests/assets/age-test-key.txt | awk '{print $NF}'

# 3. Create a .sops.yaml override for the test secrets path
#    (or add a creation_rule to the existing .sops.yaml)

# 4. Create and encrypt the dummy secrets file
nix run nixpkgs#sops -- --encrypt \
  --age $AGE_PUBKEY \
  --output tests/assets/test-secrets.yaml \
  /dev/stdin <<EOF
hermes-env: |
  GITHUB_TOKEN="TEST_TOKEN_WITH_EQUALS_AAA1234567890==suffix"
  ELEVENLABS_API_KEY="test-elevenlabs-key"
  DISCORD_BOT_TOKEN="test-discord-token"
EOF
```

---

## Test Cases (initial set)

### 1. `activation-git-credentials`

Verifies the `hermes-git-credentials` activation script:
- `.git-credentials` is written with correct content
- File has mode `0600`
- File is owned by the hermes user
- Token revocation: if `GITHUB_TOKEN` is absent, file is removed

```nix
{
  name = "activation-git-credentials";
  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [ sops-nix.nixosModules.sops ../hosts/hermes/provision.nix ];

    # Inject test age key at boot
    boot.initrd.postDeviceCommands = ''
      mkdir -p /run/secrets
      cat ${./assets/age-test-key.txt} > /etc/test-age-key.txt
    '';

    sops.age.keyFile = "/etc/test-age-key.txt";
    sops.defaultSopsFile = ./assets/test-secrets.yaml;
    sops.secrets."hermes-env" = { owner = "hermes"; mode = "0400"; };

    # Minimal user + service config matching the real host
    users.users.hermes = {
      isSystemUser = true;
      group = "hermes";
      home = "/var/lib/hermes";
      createHome = true;
    };
    users.groups.hermes = {};

    # Stub out hermes-agent-setup dependency
    system.activationScripts.hermes-agent-setup = "true";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    # File exists with correct permissions
    machine.succeed("test -f /var/lib/hermes/.git-credentials")
    machine.succeed("stat -c%a /var/lib/hermes/.git-credentials | grep -q 600")
    machine.succeed("stat -c%U /var/lib/hermes/.git-credentials | grep -q hermes")
    # Content is correct
    machine.succeed("grep -q 'https://yui-hermes:test-token-value@github.com' /var/lib/hermes/.git-credentials")
  '';
}
```

### 2. `activation-soul-md` (stretch goal for this PR)

Verifies the `hermes-soul-md` one-shot provisioning script:
- `SOUL.md` is written on first boot
- Subsequent activations do not overwrite it
- `.hermes/` directory has correct ownership

---

## Flake Integration

Add to `flake.nix` under `checks`:

```nix
checks = forDevSystems (system:
  let pkgs = nixpkgs.legacyPackages.${system};
  in {
    pre-commit-check = ...;  # existing

    # NixOS VM tests (Linux only — QEMU not available on darwin)
  } // lib.optionalAttrs (system == "x86_64-linux") {
    activation-git-credentials = pkgs.callPackage ./tests { inherit sops-nix; };
  }
);
```

Note: VM tests only run on `x86_64-linux` — QEMU/KVM not available on
`aarch64-darwin`. macOS contributors can still run `pre-commit-check`.

---

## .sops.yaml Update

Add a creation rule for the test assets so sops knows how to encrypt them:

```yaml
- path_regex: tests/assets/.*\.yaml$
  key_groups:
    - age:
        - <test-age-public-key>
```

The test age key public key is NOT the host key — it's the throwaway test key.

---

## Testing Ladder (also document in AGENTS.md)

| Change type | Tool | Root? |
|---|---|---|
| Nix eval / syntax | `nix flake check --no-build` | No |
| Package add / module option | `nixos-rebuild dry-build --flake .#nixos-hermes` | No |
| systemd unit change | `nixos-rebuild dry-activate` | Yes |
| Activation script change | `nixosTest` VM (`nix build .#checks.x86_64-linux.<test>`) | No |
| Real secrets / hardware / network | `nixos-rebuild test` | Yes |

Right tool, right job. Don't run a VM test for a package addition.
Don't call `nixos-rebuild test` to catch a Nix eval error.

---

## Also Fix in This PR

`provision.nix` currently has `***` in the grep pattern on line 50 — a
terminal secret-masking artifact that crept in during a previous edit. Fix:

```nix
# Wrong (current):
token=$(grep "^GITHUB_TOKEN=***  ...

# Correct:
token=$(grep "^GITHUB_TOKEN=" ...
```

---

## Validation

1. `nix build .#checks.x86_64-linux.activation-git-credentials` — test passes
2. `nix build .#checks.x86_64-linux.pre-commit-check` — hooks still pass
3. `nix flake show` — new check appears in output
4. Verify test assets are committed and not gitignored

---

## Risks & Mitigations (resolved)

- **`hermes-agent-setup` stub** — resolved by importing the real
  `hermes-agent.nixosModules.default` with `services.hermes-agent.enable = true`.
  The activation scripts run exactly as on the live host. The agent service
  starts but produces deprecation warnings (harmless — no valid runtime config).

- **Age key injection (initrd vs stage-2 boundary)** — `sops.age.keyFile`
  explicitly rejects Nix store paths (world-readable, security constraint).
  `boot.initrd.postDeviceCommands` is therefore required to copy the key to
  `/run/age-keys.txt` before activation. This is the same pattern sops-nix
  uses in its own integration tests. `chmod 600` used (corrected from the
  `chmod 700` in the sops-nix reference — execute bit unnecessary on a key file).

- **`forDevSystems` vs Linux-only** — resolved with
  `nixpkgs.lib.optionalAttrs (system == "x86_64-linux")` in `checks`.
  Pre-commit hooks run on both platforms; VM tests run on Linux only.

- **Test secrets content** — dummy values use edge-case characters (`=` in
  token, special chars in other values) to stress-test parsing. SOPS ciphertext
  excluded from typos and yamllint scanners via `_typos.toml` and inline
  yamllint config. Test age key allowlisted in `.gitleaks.toml`.

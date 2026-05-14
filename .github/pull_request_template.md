## Summary

-

## Linear

- Issue(s):

## GitButler branch/stack evidence

- Branch:
- Stack shape: independent / stacked on `<branch>`
- Commit(s):
- GitButler CLI `but status -fv` reviewed: yes / no
- If stacked, explain why the dependency is intentional:

## Testing ladder evidence

Paste exact commands and results. Mark skipped gates as `NOT RUN` and explain why.

| Gate | Command | Result | If not run, why |
| --- | --- | --- | --- |
| Flake eval/check | `nix flake check --no-build --no-eval-cache` |  |  |
| Pre-commit/static checks | `nix build .#checks.x86_64-linux.pre-commit-check --no-link` |  |  |
| Host dry-build | `nixos-rebuild dry-build --flake .#nixos-hermes` |  |  |
| Systemd dry-activate | `nixos-rebuild dry-activate --flake .#nixos-hermes` |  |  |
| VM activation test | `nix build .#checks.x86_64-linux.<vm-test> --no-link` |  |  |
| Real-host test | `nixos-rebuild test --flake .#nixos-hermes` |  |  |
| Real-host switch | `nixos-rebuild switch --flake .#nixos-hermes` |  |  |

## Mechanical-risk checklist

- [ ] New Nix files are imported or intentionally documented as standalone.
- [ ] New scripts/apps are reachable from a flake app, check, or documented command.
- [ ] Package/tool runtime dependencies are supplied hermetically, not assumed from ambient PATH.
- [ ] Secrets/SOPS changes were validated against declared `sops.secrets` bindings.
- [ ] Service/systemd changes include the appropriate dry-build, dry-activate, VM, or host runtime evidence.
- [ ] Docs-only or template-only changes explain why heavier NixOS gates were skipped.

## Runtime follow-up

List any commands that must be run on the host after merge, or write `none`.

-

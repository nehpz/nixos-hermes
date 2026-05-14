# Evidence Comment Examples

These examples show the shape of evidence comments. They are examples only; do not copy issue IDs, branches, or commit hashes into real work.

## NixOS Module or Package Change

```markdown
Implementation ready for review.

- Issue: <issue-id>
- PR or compare URL: https://github.com/<owner>/<repo>/pull/<number>
- Branch: `<actor>/<issue-id>`
- Commits: `<sha>`
- Changed files:
  - `modules/<file>.nix` — explains the module/package behavior change.
  - `tests/<file>.nix` — covers the changed evaluation or runtime path.

Validation:

```console
nix flake check --no-build --no-eval-cache
nix build .#checks.x86_64-linux.<check-name> --no-eval-cache
```

Results:

- Both commands passed from an isolated archive of the PR commit.
- Skipped checks: none.

Runtime/deployment follow-up:

- None; merge-only change.

Known risks:

- Low; no service behavior change intended.

GitButler / stack notes:

- Stack relationship: independent.
- Push policy: final pushed head; avoid push churn until review.
```

## Pure Prose Docs Change

```markdown
Implementation ready for review.

- Issue: <issue-id>
- PR or compare URL: https://github.com/<owner>/<repo>/pull/<number>
- Branch: `<actor>/<issue-id>`
- Commits: `<sha>`
- Changed files:
  - `AGENTS.md` — clarifies agent workflow guidance.

Validation:

```console
nix fmt AGENTS.md
```

Results:

- Formatting passed / no changes.
- Skipped checks: `nix flake check --no-build --no-eval-cache`; prose-only edit does not name new flake outputs, module imports, service names, store paths, or executable commands.

Runtime/deployment follow-up:

- None.

Known risks:

- Docs can go stale; keep exact commands close to executable checks when possible.

GitButler / stack notes:

- Stack relationship: independent.
- Push policy: final pushed head; avoid push churn until review.
```

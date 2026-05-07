# GitButler Workflow

This repository is configured for GitButler's `but` CLI. Use it as the default write interface for version-control work in this workspace.

## Installed workspace skill

The GitButler agent skill is installed locally at:

```text
.agents/skills/gitbutler/
```

It was installed with:

```bash
but skill install --path .agents/skills/gitbutler
```

Check it with:

```bash
but skill check --local
```

The skill is committed to the repository so coding agents can discover the same GitButler rules without relying on a global home-directory install.

## Workspace setup

GitButler has been initialized for this repository with:

```bash
but setup
```

Current project target:

```text
origin/main
```

After setup, GitButler checks out the synthetic `gitbutler/workspace` branch. Do not commit directly to that branch with `git commit`; GitButler owns it. Use `but commit`, `but amend`, `but absorb`, `but move`, and related commands instead.

## Agent rules

When an agent works in this repository:

1. Read `.agents/skills/gitbutler/SKILL.md` before any version-control write operation.
2. Start write workflows with:

   ```bash
   but status -fv
   ```

3. Use `but` for version-control mutations:

   | Task | Command family |
   | --- | --- |
   | inspect workspace | `but status -fv`, `but diff`, `but show` |
   | create branch | `but branch new <name> --status-after` |
   | commit selected changes | `but commit <branch-id> -m "message" --changes <file-id>,<file-id> --status-after` |
   | amend/absorb fixups | `but amend`, `but absorb` |
   | push | `but push` |
   | create PR | `but pr new` |

4. Use IDs from `but status -fv`, `but diff`, or `but show`. Do not invent IDs.
5. Always include `--status-after` on mutating `but` commands when the command supports it.
6. Read-only `git` inspection is still fine (`git log`, `git show`, `git diff --stat`, etc.). Avoid `git add`, `git commit`, `git checkout`, `git merge`, `git rebase`, `git stash`, and `git push` in this workspace.
7. The repository rule still stands: never push autonomously. `but push` is subject to the same approval boundary as `git push`.

## Pre-commit hooks

`but setup` preserves the existing pre-commit hook as:

```text
.git/hooks/pre-commit-user
```

and installs a GitButler-managed wrapper at:

```text
.git/hooks/pre-commit
```

The wrapper does two useful things:

1. It runs the existing user/pre-commit hook first.
2. It blocks accidental direct `git commit` on `gitbutler/workspace` and tells the user to use `but commit` instead.

That means the Nix/gitleaks/yaml/actionlint/formatting hooks continue to run for GitButler commits, while direct commits to the synthetic workspace branch are rejected. Do **not** bypass hooks with `but commit -n` unless the user explicitly asks and accepts the risk.

The flake-level check remains the authoritative CI-compatible validation:

```bash
nix flake check --no-build --no-eval-cache
```

For package or module changes, also run:

```bash
nixos-rebuild dry-build --flake .#nixos-hermes
```

## Common pitfalls

- `gitbutler/workspace` is not a normal feature branch. Do not rebase, merge, or commit to it directly.
- `but commit <branch>` without `--changes` can commit all uncommitted changes to that branch. Agents should prefer explicit `--changes <ids>`.
- Unrelated local files should stay uncommitted. Use `but status -fv` and commit only the file IDs that belong to the current task.
- If hooks modify files, rerun `but status -fv`, inspect the new IDs, and include the hook changes intentionally in the follow-up commit.

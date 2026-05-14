---
name: agent-workflow-reliability
description: Use when improving how agents choose work, validate changes, report evidence, or respond to deterministic misses. Focuses on durable workflow gates, honest uncertainty, retcon writing, GitButler discipline, and reusable templates.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [agents, reliability, validation, gitbutler, evidence]
    related_skills: [gitbutler]
---

# Agent Workflow Reliability

## Overview

Use this skill to turn an escaped deterministic miss into a stronger future workflow. The target is not faster closeout. The target is a durable operating system for agents: clear work selection, explicit assumptions, validation that matches the risk, and evidence a reviewer can trust after context compaction.

Good reliability work changes the next agent's default path. It should remove ambiguity, prevent a repeat failure, or make uncertainty visible early enough that a human can correct course.

## When to Use

Use this skill when:

- Review, CI, or runtime catches a miss that routine agent work should have caught.
- Updating `AGENTS.md`, local agent skills, PR/review gates, validation ladders, or evidence templates.
- A task needs a retcon-style statement of the desired end state.
- A handoff, Linear comment, PR body, or skill update risks becoming issue-closeout theater instead of useful evidence.

Do not use it merely because a task has a Linear issue. Ordinary implementation work should use the relevant implementation skill first; load this skill only for workflow-hardening behavior.

## Operating Model

1. **Understand the failure before editing.** Read the review comments, issue text, affected files, and existing skills/templates. If the domain concept is unclear, say so and research it before writing rules about it.
2. **Fix the class of failure, not the symptom.** Prefer one durable gate, template, invariant, or skill correction over a bespoke note that future agents will not see.
3. **Keep durable artifacts generic.** Skills must not name ephemeral projects, temporary issue IDs, one-off branches, or session-specific closeout mechanics except inside examples/templates explicitly marked as examples.
4. **Separate behavior, templates, and examples.** `SKILL.md` describes when and how to act. Put reusable fill-in templates under `templates/`; put worked examples or rationale under `references/` if needed.
5. **Use GitButler-native inspection and mutation in this repo.** Start with `but status -fv`, `but diff`, and `but show`. Use `but` for all version-control writes. Use GitHub/`gh` for PR metadata and review comments. Native `git` is a narrow fallback for immutable object inspection or archive validation, not the default workflow interface.
6. **Validate the artifact, not the hope.** Choose checks based on the risk introduced by the change. If validation is skipped, record the exact reason and residual risk.
7. **Leave evidence after quality is true.** Evidence comments summarize finished, validated work; they are not a substitute for understanding or review.

## Retcon Writing

Retcon is a writing style, not a document type. Use it to define the deterministic end state as if it already exists, so future agents see the desired workflow directly instead of a historical apology.

A retcon-style workflow update:

- States the current correct behavior in present tense.
- Names the gate that catches the class of miss.
- Avoids “previously we did X, now do Y” unless the historical context is operationally necessary.
- Makes uncertainty explicit instead of laundering guesses into rules.

Use this shape when documenting the correction:

```markdown
## Workflow correction

- Escaped miss: <what reached review, CI, or runtime>
- Current reliable behavior: <present-tense rule or workflow>
- Gate: <check, invariant, template field, or review step that catches it>
- Evidence: <PR, commit, command output, or issue link>
- Residual risk: <none, or what still needs human/runtime confirmation>
```

## Evidence Comments

Use `templates/evidence-comment.md` for final handoff comments. Keep the template outside this skill body so the operating instructions and fill-in artifact do not drift together.

Evidence is useful only after the work is actually ready for review. Do not optimize for moving issues through Linear. A good evidence comment tells a reviewer:

- What changed and why.
- Which exact branch/PR/commit contains the change.
- Which validation commands ran against that commit.
- Which checks were intentionally skipped and why.
- What risk remains.
- Whether GitButler stack state affects interpretation of the PR.

If a later amend changes the PR head, add fresh evidence with the final commit hash. Do not leave stale evidence as the newest record.

## Validation Ladder Rules

Pick the lightest check that covers the risk, then be honest about what it does not cover.

| Change type | Minimum useful validation | Escalate when |
|---|---|---|
| Pure prose docs | Read rendered/diffed text; format or spellcheck if available | Text names exact repo facts, commands, paths, services, options, or outputs |
| Agent skill/template | Validate frontmatter and file shape; inspect loaded instructions for drift | The skill names executable commands or repo-specific invariants |
| `AGENTS.md` / workflow rules | Read the affected section and verify referenced local paths exist | Rules name Nix commands, GitButler commands, or host/service behavior |
| Nix eval/module/package change | `nix flake check --no-build --no-eval-cache` | Closure, activation, service, or switch-time behavior changes |
| Package/service closure change | `nixos-rebuild dry-build --flake .#nixos-hermes` | systemd activation ordering or runtime host state is the risk |
| Activation/switch behavior | Repo VM test such as `nix build .#checks.x86_64-linux.<test>` | The VM test does not cover host-only secrets, hardware, or network state |
| Real secrets/hardware/network | State what local checks can prove; require operator/runtime validation | The change can affect production data, credentials, or machine access |

Validate from the PR commit when multiple GitButler branches are applied. A dirty workspace check is not proof of the PR.

## Review-Comment Response Loop

When a review requests changes on workflow docs or skills:

1. Fetch exact review comments and unresolved threads.
2. Group comments by underlying design problem, not by line number.
3. Decide whether the PR shape is wrong. If a guide duplicates a skill, or a template is embedded in prose, fix the structure before polishing words.
4. Patch the durable artifact and remove drift surfaces.
5. Validate changed files and the repo-level checks required by the touched content.
6. Push once, after the batch is coherent.
7. Resolve only comments that are actually addressed or made outdated by the new diff.

## Common Pitfalls

1. **Issue-closeout theater.** Linear evidence and state transitions should follow quality, not drive it.
2. **Pretending to know a domain term.** If a concept like retcon is fuzzy, pause and research/ask before encoding it into a skill.
3. **Ephemeral durable content.** A committed skill should not mention transient project names or one-time issue IDs except in clearly marked examples.
4. **Template sprawl.** Keep templates in `templates/`; keep examples in `references/`; keep `SKILL.md` focused on behavior.
5. **GitButler bypass by habit.** In this repo, default to `but` inspection/mutation. Do not normalize native `git` as the agent path just because it is familiar.
6. **Validation overclaiming.** Name exactly what the check proves and what remains unproven.
7. **Resolving review threads prematurely.** A thread is resolved when the design issue is addressed, not when a line changed.

## Verification Checklist

- [ ] Review/issue context was read before writing rules.
- [ ] Durable skill content is generic and not tied to ephemeral projects.
- [ ] Retcon text describes the desired end state in present tense.
- [ ] Templates/examples live outside `SKILL.md`.
- [ ] GitButler commands were used for workspace inspection/mutation.
- [ ] Validation matches the risk tier and names residual risk.
- [ ] Evidence is posted only after the change is coherent and validated.

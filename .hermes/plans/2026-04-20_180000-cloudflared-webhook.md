# Plan: Cloudflare Tunnel + Hermes Webhook for GitHub PR Events

**Date:** 2026-04-20
**Status:** Draft — pending CF tunnel token and subdomain decision from nehpz

---

## Goal

Replace the 30-minute cron polling for GitHub notifications with an event-driven
webhook. GitHub POSTs PR events in real time to a Hermes webhook listener exposed
via a Cloudflare Tunnel running as a NixOS systemd service on this host.

---

## Current State

- Cron job `github-notifications` (job ID: 17023bfefe4d) polls `/notifications`
  every 30 minutes
- Hermes webhook platform is not enabled
- No ports publicly exposed on nixos-hermes
- Cloudflare already in the stack (Traefik on 10.0.0.93 uses CF challenge response)
- `cloudflared` is available in nixpkgs

---

## Architecture

```
GitHub → Cloudflare (tunnel) → cloudflared (nixos-hermes) → Hermes webhook listener (:8644)
```

- `cloudflared` runs as a systemd service on this host, outbound-only tunnel to CF
- Hermes webhook listener binds on localhost:8644 (or 0.0.0.0:8644 — see open questions)
- Webhook URL: something like `https://hermes-webhook.rzp.one` (subdomain TBD)
- When the Traefik VM is ready, `cloudflared` moves there; only the tunnel config changes

---

## Prerequisites (manual steps — need your input)

1. **Create a Cloudflare Tunnel** in the CF Zero Trust dashboard (one.dash.cloudflare.com):
   - Zero Trust → Networks → Tunnels → Create a tunnel
   - Name: `nixos-hermes-webhook` (or similar)
   - Copy the tunnel token — this is the secret needed below

2. **Configure the public hostname** in the tunnel:
   - Public hostname: `hermes-webhook.rzp.one` (or whatever subdomain you prefer)
   - Service: `http://localhost:8644`

3. **Generate a webhook HMAC secret** — a random string used to verify GitHub's
   POST signatures. Can be generated with: `openssl rand -hex 32`

---

## Changes Required

### 1. SOPS secrets (`hosts/hermes/secrets/`)

Add two new keys to `.secrets/hermes-secrets.yaml` and re-encrypt:

```yaml
cloudflared-tunnel-token: "<token from CF dashboard>"
hermes-webhook-secret: "<random hex string>"
```

Add bindings in `hosts/hermes/sops.nix`:

```nix
cloudflared-tunnel-token = {
  owner = "root";
  mode = "0400";
};
hermes-webhook-secret = {
  owner = "hermes";
  mode = "0400";
};
```

### 2. New module: `modules/cloudflared.nix`

```nix
{ config, pkgs, ... }:
{
  services.cloudflared = {
    enable = true;
    tunnels."nixos-hermes-webhook" = {
      credentialsFile = config.sops.secrets.cloudflared-tunnel-token.path;
      default = "http_status:404";
      ingress."hermes-webhook.rzp.one" = "http://localhost:8644";
    };
  };
}
```

> Note: nixpkgs `services.cloudflared` module uses token-based auth.
> Verify the exact option shape for the pinned nixpkgs version before
> implementing — the module API has changed across versions.

### 3. Import in `hosts/hermes/default.nix`

Add `./../../modules/cloudflared.nix` (or `../../../modules/cloudflared.nix`
depending on relative path) to the imports list.

### 4. Hermes webhook platform (`hosts/hermes/sops.nix` + `modules/hermes-agent.nix`)

Enable the webhook platform in the hermes-agent settings:

```nix
settings = {
  # ... existing settings ...
  platforms.webhook = {
    enabled = true;
    extra = {
      host = "127.0.0.1";  # localhost only — cloudflared is the ingress
      port = 8644;
      # secret injected via environmentFiles from sops
    };
  };
};
```

The `WEBHOOK_SECRET` env var needs to be added to the `hermes-env` sops secret
(or injected separately). Since `hermes-env` is an opaque env file, the cleanest
approach is to inject `WEBHOOK_SECRET` via a separate `environmentFiles` entry
pointing at `config.sops.secrets.hermes-webhook-secret.path`.

> Open question: does hermes-agent module support multiple `environmentFiles`?
> Check upstream module — if not, merge into the existing `hermes-env` secret.

### 5. GitHub webhook subscription (runtime, after rebuild)

Once the tunnel is live and Hermes webhook platform is enabled:

```bash
hermes webhook subscribe github-prs \
  --events "pull_request,pull_request_review,pull_request_review_comment" \
  --prompt "..." \
  --deliver origin
```

Register the webhook in the nehpz/nixos-hermes repo:
- Payload URL: `https://hermes-webhook.rzp.one/<subscription-path>`
- Content type: `application/json`
- Secret: the HMAC secret from sops
- Events: Pull requests, Pull request reviews, Pull request review comments

### 6. Retire the cron job

```bash
# After verifying webhook is receiving events
hermes cronjob remove 17023bfefe4d
```

---

## Prompt Design (webhook subscription)

The webhook fires on every push — need to filter to actionable events only.
The prompt should:

- Ignore `synchronize` and `opened` actions on our own PRs (yui-hermes authored)
- Trigger on `review_requested` where requested reviewer is yui-hermes
- Trigger on `pull_request_review` where PR author is yui-hermes (new review from nehpz)
- Trigger on `pull_request_review_comment` on PRs authored by yui-hermes

Draft prompt:

```
A GitHub event has arrived for nehpz/nixos-hermes.

Event: {action} on PR #{pull_request.number} "{pull_request.title}"
PR author: {pull_request.user.login}
Sender: {sender.login}

{pull_request.body}

Rules:
- If action is "review_requested" and you are the requested reviewer: review the PR,
  leave inline comments, and approve or request changes.
- If action is "submitted" (review) and PR author is "yui-hermes": read the review,
  address any feedback with commits, then push.
- If action is "created" (review comment) on a yui-hermes PR: read the comment and
  respond or fix as appropriate.
- Otherwise: do nothing.
```

---

## Validation Steps

1. `nix build .#nixosConfigurations.nixos-hermes.config.system.build.toplevel` —
   confirm config evaluates
2. `nix build .#checks.x86_64-linux.pre-commit-check` — all hooks pass
3. After rebuild: `systemctl status cloudflared-tunnel-nixos-hermes-webhook` — tunnel running
4. `curl https://hermes-webhook.rzp.one/health` — reachable from outside
5. `hermes webhook list` — subscription visible
6. GitHub → repo Settings → Webhooks → Recent Deliveries — verify test ping delivers
7. Open a test PR, confirm webhook fires and agent responds correctly
8. Remove cron job only after step 7 confirmed

---

## Related: git-credentials persistence (`provision.nix`)

`~/.git-credentials` is currently wiped on every rebuild by sops-nix activation
overwriting `~/.hermes/.env`. The token is now in sops via `hermes-env`, so the
fix is an activation script in `provision.nix` that writes `~/.git-credentials`
from the decrypted env on every activation (not just first boot):

```bash
source /run/secrets/hermes-env
echo "https://yui-hermes:${GITHUB_TOKEN}@github.com" > /var/lib/hermes/.git-credentials
chmod 600 /var/lib/hermes/.git-credentials
```

This should be added to `provision.nix` alongside the cloudflared work, since
we'll already be touching activation scripts.

---

## Risks & Open Questions

- **`services.cloudflared` module API** — needs verification against the pinned nixpkgs
  version before writing the module. The option paths have shifted between releases.
- **`environmentFiles` list support** — need to confirm hermes-agent module accepts
  multiple env files, otherwise merge `WEBHOOK_SECRET` into the existing `hermes-env` secret.
- **Webhook listener bind address** — `127.0.0.1` vs `0.0.0.0`. Since cloudflared
  runs on the same host and terminates locally, `127.0.0.1` is correct and tighter.
- **Tunnel token format** — CF tunnel tokens are either a token string (newer) or a
  credentials JSON file (older). The nixpkgs module expects one or the other depending
  on version — verify before adding to sops.
- **Re-encrypting secrets** — `.secrets/hermes-secrets.yaml` is gitignored and only
  exists locally. If it doesn't exist on this host, a new plaintext template needs to
  be seeded before adding keys and re-encrypting. Check with `ls .secrets/`.
- **Cron retirement timing** — keep the cron running in parallel until the webhook
  is confirmed working end-to-end. Don't remove it prematurely.

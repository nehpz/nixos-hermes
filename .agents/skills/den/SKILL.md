---
name: den
description: "Use when designing, reviewing, documenting, or implementing Den-based Nix configurations. Enforces Den's entity/aspect/policy/quirk model and the homelab conventions for semantic, low-copy-paste declarative infrastructure."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [nix, den, dendritic, homelab, declarative-infra]
    related_skills: [gitbutler]
---

# Den

## Overview

Den is both a domain-agnostic Nix library and a NixOS/Darwin/Home Manager framework. Treat it as an aspect-oriented, context-driven data transformation pipeline: entities declare what exists, aspects declare behavior, policies declare topology, and quirks/pipes move structured data without coupling producers to consumers.

For this repository's future homelab migration, strict adherence to Den's model is expected. Do not translate Den back into host-first Nix with prettier folders. The point is semantic infrastructure with reusable cross-class aspects and minimal copy/paste.

Primary references:

- Local research clone: `external/den`
- Official docs in clone: `external/den/docs/src/content/docs`
- Upstream docs: https://den.denful.dev
- Upstream source: https://github.com/denful/den
- Homelab conventions: `references/homelab-conventions.md`

## When to Use

Use this skill when:

- Designing or reviewing a Den migration.
- Modeling non-NixOS hosts such as Unraid, Pop!_OS, CachyOS, macOS, firmware appliances, or mutable Linux systems inside a declarative fleet without pretending they are NixOS.
- Writing Den aspects, schemas, policies, quirks, or namespaces.
- Documenting the homelab architecture in retcon style.
- Deciding whether a concern belongs in entity metadata, an aspect, a policy, a quirk, or a custom class.
- Creating reusable Den conventions or examples for hosts, workloads, users, microVMs, cloud infra, monitoring, DNS, backups, or reverse proxies.

Do not use Den merely as a folder layout. If the change is still host-first and copy/pasted, it is not Den-shaped.

## Mental Model

Den has four core concerns:

| Concern | Purpose | Lives in |
|---|---|---|
| Entity | Typed record for what exists | `den.hosts`, `den.homes`, `den.schema.*` |
| Aspect | Reusable behavior across Nix classes | `den.aspects.*`, namespaced aspects |
| Policy | Topology, context enrichment, routing, instantiation | `den.policies.*` |
| Quirk | Structured data emitted/collected by aspects | `den.quirks.*`, `den.lib.policy.pipe.*` |

Rules of thumb:

- Facts go in schema/entity metadata.
- Behavior goes in aspects.
- Relationships and traversal go in policies.
- Aggregated operational data goes in quirks/pipes.
- Reusable libraries go in namespaces.
- Generated docs/diagrams come from the Den graph, not hand-maintained architecture drawings.

## Library vs Framework

Den's library (`den.lib`) is domain-agnostic. It can resolve aspects for any Nix module system: Terranix, NixVim, MicroVMs, flake-parts perSystem modules, custom workload modules, and more.

Den's framework builds on the library for OS/user configuration:

- `den.hosts` and `den.homes` declare infrastructure entities.
- `den.schema` defines typed metadata and custom entity kinds.
- `den.aspects` composes behavior into Nix classes such as `nixos`, `darwin`, `homeManager`, `user`, `hjem`, `maid`, or custom classes.
- `den.policies` walks the entity graph and instantiates outputs.
- `den.provides` supplies batteries like `define-user`, `hostname`, `primary-user`, `forward`, and home-environment integration.

Use the framework for NixOS/Darwin/Home Manager hosts. Use the library directly or via custom classes for workloads and infra domains that are not OS configs.

## Authoring Pattern

### 1. Declare entities as inventory

Host declarations are facts, not implementation dumps:

```nix
den.hosts.x86_64-linux.nas = {
  site = "home";
  environment = "prod";
  role = "storage-node";
  addr = "10.0.0.10";
  storage.zfs = true;
  workloads = [ "samba" "restic" "prometheus-node" ];
  users.alice.primary = true;
  users.backup.service = true;
};
```

### 2. Keep concrete host aspects thin

Concrete host aspects mostly include semantic bundles:

```nix
den.aspects.nas.includes = [
  lab.roles.storage-node
  lab.features.zfs
  lab.features.backups
  lab.features.monitoring-agent
  lab.workloads.samba
];
```

If a host aspect contains a long NixOS module, stop and ask whether the behavior belongs in `lab.roles.*`, `lab.features.*`, `lab.workloads.*`, or `lab.hardware.*`.

### 3. Use aspects for one concern across all classes

A workload aspect can configure NixOS, Home Manager, Terranix, monitoring quirks, reverse proxy quirks, and backup quirks together:

```nix
lab.workloads.forgejo = {
  includes = [ lab.features.postgresql lab.features.reverse-proxy ];

  nixos = { host, ... }: {
    services.forgejo.enable = true;
    services.forgejo.settings.server.DOMAIN = "forgejo.${host.domain}";
  };

  monitoring-targets = { host, ... }: {
    name = "forgejo";
    address = host.addr;
    port = 3000;
  };

  reverse-proxy-vhosts = { host, ... }: {
    domain = "forgejo.${host.domain}";
    upstream = "http://${host.addr}:3000";
  };
};
```

### 4. Use schema for vocabulary

Declare recurring host/user/workload fields in `den.schema.*`. Freeform fields are fine while exploring, but schemas are how the homelab becomes self-documenting and typo-resistant.

Typical host schema fields:

- `site`
- `environment`
- `role`
- `addr`
- `domain`
- `fqdn`
- `vlan`
- `tags`
- `workloads`
- `backup.enable`
- `monitoring.enable`
- `hardware.gpu`
- `storage.zfs`
- `infra.provider`
- `infra.region`

Schema is metadata. Do not hide NixOS implementation inside schema unless defining schema options/defaults.

### 5. Use policies for topology

Policies are context functions returning policy effects. They define relationships such as:

- flake → site → environment → host → user
- host → workload
- host → microvm guest
- environment → hosts
- host → cloud infra outputs

Use `den.lib.policy.resolve.to`, `include`, `provide`, `route`, `instantiate`, and `pipe.from` constructors. Do not hand-roll effect attrsets.

### 6. Use quirks/pipes for data flow

Use quirks for data that many producers emit and one or more consumers assemble:

- `monitoring-targets`
- `reverse-proxy-vhosts`
- `dns-records`
- `backup-jobs`
- `firewall-rules`
- `http-backends`
- `dashboard-links`

Quirk consumers receive lists via class module args. Include ordering does not matter; Den defers consumers until pipe data is assembled.

### 7. Use namespaces for reusable libraries

Concrete fleet entities can live in `den.aspects.*`. Reusable building blocks should live in a local namespace, e.g. `lab`:

```nix
imports = [ (inputs.den.namespace "lab" true) ];
_module.args.__findFile = den.lib.__findFile;
```

Recommended namespace shape:

```text
lab.roles.*
lab.features.*
lab.workloads.*
lab.hardware.*
lab.platform.*
lab.infra.*
lab.users.*
```

## Retcon Documentation Style

Write docs as if the Den-based homelab already exists and the document describes reality.

Avoid:

> We will add monitoring targets later.

Prefer:

> Workloads emit `monitoring-targets`. The monitoring collector policy assembles targets within each environment, and the Prometheus aspect renders scrape configs from the resulting quirk data.

Avoid:

> To avoid duplication, you can put hosts in roles.

Prefer:

> Host aspects are small composition points. `nas` includes `lab.roles.storage-node`, `lab.features.zfs`, and the workloads that run on the storage node.

The goal is architectural clarity, not migration promises.

## Common Pitfalls

1. **Host-first relapse.** Large `den.aspects.<host>.nixos = { ... }` blocks recreate old NixOS host files. Extract features, roles, workloads, hardware, or platform aspects.

2. **Using schema as behavior.** Schema defines typed facts. Aspects consume those facts to produce behavior.

3. **Using stringly tags instead of aspect references.** `includes` should contain real aspects/policies, not strings.

4. **Comparing entities directly.** Use `id_hash`, not `==`, when filtering/comparing hosts/users/homes.

5. **Confusing class and entity kind.** `nixos`, `darwin`, `homeManager`, `user` are classes. `host`, `user`, `home`, `fleet`, custom `environment`/`workload` are entity kinds.

6. **Undeclared class keys.** Register custom classes in `den.classes` or via the relevant battery. Otherwise aspect keys may be interpreted incorrectly.

7. **Quirk/class name collisions.** `den.quirks` keys must not overlap `den.classes`.

8. **Overusing `den.default`.** Defaults are for true fleet-wide baselines only: state versions, hostname/user batteries, baseline Nix/SSH if universal.

9. **Cross-host recursion.** Config-dependent cross-host pipe thunks must form a DAG. Host A reading host B while B reads A is a Nix recursion trap.

10. **Pretending non-NixOS hosts are NixOS.** Unraid, Pop!_OS, CachyOS, macOS, and appliances can be Den `host` entities, but they must use appropriate classes (`externalLinux`, `unraid`, `darwin`, `monitoring`, `docs`, etc.) instead of bogus `nixos` output.
11. **Ignoring official tests/templates.** Den's `templates/ci/modules/features/*.nix` are executable examples. Read them before inventing patterns.

## Verification Checklist

Before committing Den docs or code:

- [ ] The source clone/docs were checked for the specific construct being described.
- [ ] Host declarations remain inventory-like.
- [ ] Reusable behavior is in named aspects, not copied host modules.
- [ ] Policies use Den policy constructors.
- [ ] Quirks are declared centrally before producers/consumers rely on them.
- [ ] New vocabulary belongs in `den.schema.*` if it recurs.
- [ ] Custom classes are registered and forwarded explicitly.
- [ ] Docs use retcon style and avoid “will eventually” language.
- [ ] Examples distinguish entity kinds from Nix classes.
- [ ] Validation commands are appropriate for the containing repo.

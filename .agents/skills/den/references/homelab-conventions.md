# Den Homelab Conventions

This reference captures the Den conventions for the homelab Nix migration. It is written as operating doctrine: Den is the semantic model for hosts, users, workloads, infrastructure outputs, and generated architecture docs.

## Repository Shape

The Den configuration is organized by meaning:

```text
modules/
  den.nix
  defaults.nix
  systems.nix

  schema/
    host.nix
    user.nix
    environment.nix
    workload.nix
    microvm.nix
    infra.nix

  entities/
    hosts.nix
    homes.nix
    users.nix
    environments.nix
    workloads.nix

  aspects/
    hosts/
    users/
    roles/
    features/
    workloads/
    hardware/
    platform/
    infra/

  policies/
    topology.nix
    pipes.nix
    microvm.nix
    terranix.nix

  namespaces/
    lab.nix
    imports.nix

  diagrams/
    views.nix
    outputs.nix
```

Teaching templates in Den keep files small for clarity. The homelab splits aggressively by semantic concern.

## Vocabulary

### Entities

Entities are records of what exists:

- `host`: machines and VM guests.
- `user`: identities attached to hosts.
- `home`: standalone Home Manager homes.
- `environment`: prod/staging/lab/dev grouping.
- `site`: physical or provider location, when needed.
- `workload`: application/service inventory, when explicit workload entities clarify topology.
- `fleet`: grouped host collection for cross-host pipes.

### Aspects

Aspects are behavior:

- `roles.*`: bundles of capabilities for a host kind.
- `features.*`: reusable low-level capabilities.
- `workloads.*`: app/service definitions.
- `hardware.*`: hardware-specific behavior.
- `platform.*`: NixOS/Darwin/WSL/MicroVM platform concerns.
- `infra.*`: cloud/resource-provider concerns.
- `users.*`: identity behavior.

### Policies

Policies define transitions and data routing. Names are verbs or arrows:

- `to-sites`
- `site-to-environments`
- `environment-to-hosts`
- `host-to-workloads`
- `host-to-microvm-guests`
- `collect-monitoring-targets`
- `collect-reverse-proxy-vhosts`

### Quirks

Quirks are plural data streams:

- `monitoring-targets`
- `reverse-proxy-vhosts`
- `dns-records`
- `backup-jobs`
- `firewall-rules`
- `http-backends`
- `dashboard-links`

## Host Inventory

A host declaration records stable facts:

```nix
den.hosts.x86_64-linux.nas = {
  site = "home";
  environment = "prod";
  role = "storage-node";
  addr = "10.0.0.10";
  domain = "home.arpa";
  storage.zfs = true;
  workloads = [ "samba" "restic" "prometheus-node" ];

  users.alice.primary = true;
  users.backup.service = true;
};
```

The host declaration does not contain the NAS implementation. It is inventory.

The host aspect composes behavior:

```nix
den.aspects.nas.includes = [
  lab.roles.storage-node
  lab.features.zfs
  lab.features.backups
  lab.features.monitoring-agent
  lab.workloads.samba
];
```

## User Model

Users are portable identities. Hosts declare which users exist; user aspects describe behavior.

```nix
den.schema.user.classes = lib.mkDefault [ "homeManager" ];

den.hosts.x86_64-linux.nas.users = {
  alice = {
    primary = true;
    groups = [ "wheel" "media" "storage" ];
    shell = "fish";
  };

  deploy = {
    service = true;
    groups = [ "wheel" ];
    sshOnly = true;
  };
};
```

User behavior lives in aspects:

```nix
lab.users.alice.includes = [
  den.provides.define-user
  den.provides.primary-user
  lab.features.shell-fish
  lab.features.git
];
```

## Workloads

A workload aspect is the single semantic source for one service. It contributes to every relevant class and emits operational data through quirks.

```nix
lab.workloads.grafana = {
  includes = [ lab.features.reverse-proxy ];

  nixos = { host, ... }: {
    services.grafana.enable = true;
    services.grafana.settings.server.domain = "grafana.${host.domain}";
  };

  monitoring-targets = { host, ... }: {
    name = "grafana";
    address = host.addr;
    port = 3000;
  };

  reverse-proxy-vhosts = { host, ... }: {
    domain = "grafana.${host.domain}";
    upstream = "http://${host.addr}:3000";
  };
};
```

The monitoring and proxy aspects consume quirk data. Workloads do not manually edit Prometheus or proxy global lists.

## Schemas

Schema defines recurring facts and defaults:

```nix
den.schema.host = { lib, config, ... }: {
  options.site = lib.mkOption {
    type = lib.types.str;
    default = "home";
  };

  options.environment = lib.mkOption {
    type = lib.types.enum [ "prod" "staging" "lab" "dev" ];
    default = "prod";
  };

  options.domain = lib.mkOption {
    type = lib.types.str;
    default = "home.arpa";
  };

  options.fqdn = lib.mkOption {
    type = lib.types.str;
    default = "${config.hostName}.${config.domain}";
  };
};
```

Schemas make host facts typed and discoverable. Aspects consume schema values through context args such as `{ host, ... }`.

## Topology Policies

The default Den flake policy groups hosts by system. The homelab topology uses explicit entities when environment/site grouping matters:

```nix
den.policies.environment-to-hosts = { environment, ... }:
  lib.concatMap
    (system:
      lib.concatMap
        (hostName:
          let host = den.hosts.${system}.${hostName}; in
          lib.optionals (host.environment == environment.name) [
            (den.lib.policy.resolve.to "host" { inherit host; })
            (den.lib.policy.instantiate host)
          ])
        (builtins.attrNames (den.hosts.${system} or {})))
    (builtins.attrNames (den.hosts or {}));
```

Topology policies are explicit because scope layout controls what `pipe.collect` can see.

## Quirk Data Flow

Workloads emit data. Collector policies assemble it. Consumers render Nix configuration from assembled data.

```nix
den.quirks.monitoring-targets.description =
  "Prometheus scrape targets emitted by hosts and workloads";

den.policies.collect-monitoring-targets = { host, ... }: [
  (den.lib.policy.pipe.from "monitoring-targets" [
    (den.lib.policy.pipe.collect ({ host, ... }: true))
    den.lib.policy.pipe.withProvenance
  ])
];
```

This pattern is used for monitoring, reverse proxying, DNS, firewall rules, backups, dashboards, and service discovery.

## Virtualization and Containers

Runtime choice follows ownership and isolation, not hype.

| Runtime shape | Den model | Use for |
|---|---|---|
| Bare metal / conventional VM running NixOS | `den.hosts.*` with `nixos` class | Machines Den deploys directly |
| Bare metal / conventional VM running non-NixOS Linux | `den.hosts.*` with `externalLinux`/platform-specific classes | Machines Den inventories and partially converges through SSH/API/agent tooling |
| MicroVM / NixOS container with Den-owned NixOS config | `den.hosts.*` with `intoAttr = [ ]` when embedded | Full OS boundary, appliance isolation, rootful tests |
| OCI container | workload aspect or custom `oci` class | Image-based app runtime, simple services |
| Incus/LXC daemon | host feature aspect | Host capability for managing instances |
| Incus project/profile/network/storage | infra aspect/entity | Manager-owned infra resources, often via preseed |
| Incus/LXC image instance | workload/infra resource unless Den owns the guest OS | Non-NixOS or image-based instances |

MicroVM guests are hosts when Den owns their OS graph. They are not special snowflakes.

```nix
den.hosts.x86_64-linux.server.microvm.guests = [
  den.hosts.x86_64-linux.home-assistant-vm
];

den.hosts.x86_64-linux.home-assistant-vm = {
  intoAttr = [ ];
  role = "microvm";
  users.alice = { };
};
```

Policies route guest configurations into the host. Guest aspects remain ordinary aspects.

MicroVMs are not the default home for every lab service. Prefer:

1. Host NixOS modules for core integrated host services.
2. OCI containers for ordinary image-packaged apps.
3. NixOS containers or MicroVMs when the service deserves a full NixOS boundary.
4. Ephemeral MicroVM runners for tests and dangerous/rootful experiments.

QEMU is the compatibility-first hypervisor and the obvious choice for local NixOS rebuild testing. Firecracker/cloud-hypervisor/crosvm are attractive for constrained long-running or ephemeral appliance patterns once the service shape is stable.

## Non-NixOS Hosts

Declarative infrastructure is a control model, not a religious requirement that every machine run NixOS. Non-NixOS machines remain `host` entities because they still have identity, hardware, network presence, users, exported services, monitoring targets, backup contracts, and workload placement constraints.

The class set changes by management authority:

| Platform | Den classes | Boundary |
|---|---|---|
| NixOS | `nixos`, plus quirks such as `monitoring-targets`/`backup-jobs` | Full declarative convergence. |
| Unraid | `unraid`, `monitoring`, `dns`, `backup`, `docs` | Appliance-managed storage; Den owns inventory and automatable integration edges. |
| Pop!_OS/CachyOS/other Linux | `systemManager` where supported, `externalLinux`, `homeManager` where appropriate, `monitoring`, `workload-placement` | Mutable distro remains optimized for its purpose; Den generates System Manager configs or fallback external management plans. |
| Network/firmware appliance | platform-specific or `docs`/`monitoring` classes | Den tracks contracts and automatable API surfaces, not imaginary OS control. |

Pattern:

```nix
den.hosts.x86_64-linux.nas = {
  role = "storage-node";
  os.distribution = "unraid";
  os.management = "appliance";
  hardware.storage.mixedSizeArray = true;
};

den.aspects.nas.includes = [
  lab.roles.storage-node
  lab.features.unraid-appliance
  lab.features.backup-target
];
```

Do not emit NixOS modules for non-NixOS hosts. Emit platform-specific desired state, scripts, API calls, documentation, monitoring targets, DNS records, backup jobs, or drift checks. If a value cannot be automatically converged, model it as an explicit manual boundary rather than burying it in tribal knowledge.

## Infra Classes

Cloud and provider resources are class outputs attached to the same semantic model. A VPS aspect can contribute both system configuration and Terranix resources:

```nix
lab.roles.vps = {
  includes = [ lab.infra.hcloud-server lab.features.ssh ];

  nixos.services.openssh.enable = true;

  terranix = { host, ... }: {
    resource.hcloud_server.${host.name} = {
      name = host.hostName;
      server_type = host.infra.server-type;
      location = host.infra.region;
    };
  };
};
```

## Documentation

Architecture documentation is retcon-style. It describes the Den graph as existing reality.

Good:

> `nas` is the storage node for the home site. Its declaration records storage and backup facts. Its aspect includes `lab.roles.storage-node`, `lab.features.zfs`, `lab.features.backups`, and the workloads that run there.

Bad:

> We will add a NAS and later configure backups.

Diagrams are generated from Den, not maintained by hand. The diagram set documents fleet overview, host detail, user detail, class slices, and provider matrices.

## Review Checklist

- Host declarations are inventory-like.
- Concrete host aspects are thin composition points.
- Reusable behavior is extracted into roles/features/workloads/hardware/platform/infra.
- Schema contains typed recurring vocabulary.
- Policies model topology and cross-entity delivery.
- Quirks carry aggregated operational data.
- Namespaces hold reusable aspect libraries.
- Docs describe the current architecture in retcon style.

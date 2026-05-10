# Den Homelab Architecture

The homelab is modeled as a Den fleet: typed entities describe what exists, aspects describe behavior, policies describe topology, and quirks move structured operational data between scopes. The configuration is semantic first. Host files are inventory, not implementation dumps.

## Operating Model

Den owns the shape of the infrastructure model.

- `den.hosts` records machines, VMs, sites, environments, and attached users.
- `den.homes` records standalone home environments where host-managed users are not the right activation boundary.
- `den.schema` defines the vocabulary shared by hosts, users, homes, workloads, environments, and infra entities.
- `den.aspects` and the local `lab` namespace hold reusable behavior.
- `den.policies` defines traversal, grouping, cross-entity delivery, and output instantiation.
- `den.quirks` carries operational data such as monitoring targets, reverse proxy vhosts, DNS records, backup jobs, firewall rules, and dashboard links.

The resulting system reads like an infrastructure graph rather than a pile of per-host modules.

## Entity Graph

The baseline graph is:

```text
flake
└── environment
    └── host
        └── user
```

Additional entity kinds are present when they clarify real topology:

```text
flake
└── site
    └── environment
        └── host
            ├── user
            ├── workload
            └── microvm-guest
```

Small installations can keep `site` and `workload` as host schema fields. Larger installations promote them into first-class entity kinds so policies can group, collect, and route data explicitly.

## Host Inventory

Hosts are declared as facts:

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

The host declaration answers:

- where the machine lives;
- what role it plays;
- which users exist there;
- which workloads belong there;
- which capabilities it advertises.

It does not contain large NixOS modules. Implementation belongs in aspects.

## Host Aspects

Concrete host aspects are composition points:

```nix
den.aspects.nas.includes = [
  lab.roles.storage-node
  lab.features.zfs
  lab.features.backups
  lab.features.monitoring-agent
  lab.workloads.samba
];
```

A host aspect that grows into a long module gets split. Stable behavior moves into one of:

- `lab.roles.*`
- `lab.features.*`
- `lab.workloads.*`
- `lab.hardware.*`
- `lab.platform.*`
- `lab.infra.*`

## Reusable Aspect Library

The local namespace is `lab`. It contains reusable homelab building blocks:

```text
lab.roles.*       # server, workstation, storage-node, edge-router, media-server
lab.features.*    # ssh, tailscale, backups, monitoring-agent, reverse-proxy
lab.workloads.*   # forgejo, grafana, prometheus, immich, jellyfin, postgresql
lab.hardware.*    # zfs, nvidia, raspberry-pi, laptop-power
lab.platform.*    # nixos-baseline, darwin-baseline, microvm-guest, wsl
lab.infra.*       # hcloud-server, dns-zone, terraform-provider
lab.users.*       # alice, deploy, backup, service users
```

Concrete `den.aspects.<host>` and `den.aspects.<user>` entries wire entity-specific composition. Reusable logic lives under `lab`.

## Schema Vocabulary

Schemas make the infrastructure vocabulary typed and discoverable.

Host metadata includes:

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

User metadata includes:

- `primary`
- `service`
- `sshOnly`
- `groups`
- `shell`
- `git.email`
- `classes`

Schema is metadata. Aspects consume metadata to render class modules.

## Workloads

A workload is one semantic service across every class it touches:

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

The workload does not edit global monitoring or proxy lists. It emits quirk data. Collector policies assemble data for consumers.

## Operational Data Flow

Operational lists are derived from quirk producers:

```nix
den.quirks.monitoring-targets.description =
  "Prometheus scrape targets emitted by hosts and workloads";

den.quirks.reverse-proxy-vhosts.description =
  "Virtual hosts emitted by workloads";

den.quirks.backup-jobs.description =
  "Backup jobs emitted by stateful services";
```

Collector policies define the visibility boundary:

```nix
den.policies.collect-monitoring-targets = { host, ... }: [
  (den.lib.policy.pipe.from "monitoring-targets" [
    (den.lib.policy.pipe.collect ({ host, ... }: true))
    den.lib.policy.pipe.withProvenance
  ])
];
```

Consumers receive assembled data via class module args:

```nix
lab.roles.monitoring-server.nixos =
  { monitoring-targets, lib, ... }:
  {
    services.prometheus.scrapeConfigs = map
      (target: {
        job_name = target.value.name;
        static_configs = [{
          targets = [ "${target.value.address}:${toString target.value.port}" ];
        }];
      })
      monitoring-targets;
  };
```

This is the normal pattern for monitoring, reverse proxying, DNS, backups, firewall rules, load balancers, and dashboards.

## Users and Homes

Users are portable identities. Host declarations state user presence. User aspects describe behavior.

```nix
den.schema.user.classes = lib.mkDefault [ "homeManager" ];

den.aspects.alice.includes = [
  den.provides.define-user
  den.provides.primary-user
  lab.features.shell-fish
  lab.features.git
];
```

Standalone homes exist when the activation boundary is user-owned rather than host-owned:

```nix
den.homes.x86_64-linux."alice@workstation" = { };
```

Host-managed and standalone homes share the same user aspects where possible.

## MicroVMs

MicroVM guests are first-class hosts. They can be hidden from top-level outputs with `intoAttr = [ ]` when they exist only through a parent host.

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

Guest behavior remains ordinary aspect composition.

## Infra Outputs

Cloud/provider resources use custom classes or library-only Den patterns. A host can contribute NixOS configuration and Terranix resources from the same aspect:

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

The host remains one semantic entity even when multiple outputs are generated from it.

## Defaults

`den.default` contains only true fleet-wide baseline behavior:

```nix
den.default = {
  nixos.system.stateVersion = "25.11";
  homeManager.home.stateVersion = "25.11";

  includes = [
    den.provides.hostname
    den.provides.define-user
    lab.features.nix-baseline
    lab.features.ssh-baseline
  ];
};
```

Role-specific behavior never belongs in `den.default`.

## Diagrams

Architecture diagrams are generated from Den's resolved graph. They are documentation artifacts backed by the same model that builds systems.

The diagram set includes:

```text
docs/architecture/
  fleet.md
  hosts/nas.md
  hosts/router.md
  users/alice.md
  classes/nixos.md
  classes/homeManager.md
  graphs/fleet-c4.svg
  graphs/provider-matrix.svg
```

The diagrams answer:

- which aspects configure a host;
- which classes a concern contributes to;
- which workloads emit which operational data;
- which policies create scope boundaries;
- which cross-host pipes feed consumers.

## Review Standard

A change is Den-shaped when:

- entities are facts;
- aspects are reusable behavior;
- policies express topology;
- quirks carry aggregated data;
- schemas define recurring vocabulary;
- concrete host aspects remain thin;
- docs describe the graph as it exists.

A change is rejected when it uses Den syntax to preserve host-first copy/paste.

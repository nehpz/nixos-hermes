# Hardware Inventory

This document records the current lab hardware as fleet inventory. It is intentionally descriptive: Den host entities consume these facts later, while roles/aspects decide what the machines do.

## Hosted Compute Services (`svc`)

Primary high-compute services node with the strongest GPU. This is the natural default for GPU-bound local AI workloads and heavyweight virtualization that benefits from CUDA/NVIDIA support.

**Motherboard**: Gigabyte AORUS Z790 Master X

**CPU**: Intel Core i9-14900K + Liquid Freezer III Pro 360

**RAM**: 192GB G.Skill Ripjaw S5 DDR5 5200MHz

- F5-5200J4040A48GX2-RS5K (x2)
- CL40-40-40-83

**GPU**: PNY GeForce RTX 4080 Super 16GB Verto OC GDDR6X

- VCG408016TFXPB1
- 3 slot; length: 340 mm; height: 143 mm
- 750W minimum

**Power**: CORSAIR RM1200e ATX 3.0 PCIe 5.0 80 PLUS Gold

**Storage (OS)**: Samsung 990 Pro PCIe 4.0 NVMe SSD DRAM V-NAND TLC

- MZ-V9P4T0B/AM
- Sequential read/write: 7,450/6,900 MB/s

**Storage (OS)**: Teamgroup MP44 4TB PCIe 4.0 NVMe SSD

- TM8FPW004T0C101
- Sequential read/write: 7,400/6,900 MB/s

**Storage (scratch / high-speed local)**: Crucial T705 2TB PCIe 5.0 NVMe SSD

- CT2000T705SSD3
- Sequential read/write: 14,500/12,700 MB/s

**Networking**: 10 GbE motherboard NIC

**Cooling**:

- Noctua NF-A8x25 PWM 80mm (x2)

**Case**: Silverstone Technologies SST-RM4A

**UPS**: Ubiquiti UniFi UPS 2U

**Fleet role notes**:

- Den role: `compute-node` / `gpu-node`.
- Virtualization role: heavyweight VM and MicroVM host.
- GPU role: default NVIDIA accelerator host.
- Good fit: vLLM/llama.cpp CUDA serving, ephemeral QEMU MicroVM test runners, GPU-backed services, build farm work, CI-like integration tests.
- Avoid making this the storage authority; keep large durable data on `nas` and mount/cache what compute workloads need.

## Network Attached Storage (`nas`)

Storage authority for the lab. This host owns the big mixed-size disk set and stays on Unraid until ZFS can handle the storage layout without a major capacity or operational drawback.

**Motherboard**: Gigabyte AORUS Z690 Ultra

**CPU**: Intel i5 13600K + BeQuiet! Dark Rock Pro 5

**RAM**: 32GB Gigabyte AORUS DDR5 5200MHz

- GP-ARS32G52D5
- Timing 40-40-40-80

**GPU**: Intel Arc B580

**Power**: CORSAIR RM750e ATX 3.1 PCIe 5.1 Cybernetics Platinum

**Storage (OS)**: Kingston 16GB DataTraveler 2.0 (Unraid)

**Storage (cache)**: Crucial BX500 3D NAND SATA

- CT2000BX500SSD

**Storage (data)**: Seagate BarraCuda 3.5 HAMR

- ST24000DM001-3Y7103 (x2)

**Storage (data)**: Seagate Exos X22 HAMR

- ST22000NM000C-3WC103

**Storage (data)**: Seagate Exos X16/X20

- ST20000NM007D-3DJ103
- ST16000NM000D-3PC101 (x2)

**Networking**: Intel X520-DA2 PCIe NIC

**Cooling**:

- be quiet! Silent Wings Pro 4 140mm (x2)
- Noctua NF-A12x25 PWM 120mm (x6)

**Case**: JONSBO N5

**UPS**: Ubiquiti UniFi UPS 2U

**Fleet role notes**:

- Den role: `storage-node`.
- Operating system: Unraid, intentionally non-NixOS.
- Virtualization role: limited; storage-adjacent containers/VMs only.
- GPU role: secondary/utility Intel Arc accelerator, not the primary AI node.
- Good fit: NAS services, backup targets, media storage, snapshot/replication coordination, low-churn storage-adjacent workloads.
- Avoid running noisy compute here unless it is explicitly storage-adjacent. Storage nodes should stay boring.

## High-Performance Compute (`rzp-hpc`)

Second high-compute node with strong CPU and weaker GPU. This is the best default for CPU-heavy virtualization, non-GPU builders, and workloads that need fast local NVMe but not the RTX 4080. It also doubles as the living-room Steam gaming machine.

**Motherboard**: ASUS ROG Maximus Z690 Formula

**CPU**: Intel Core i9-13900K + MSI MEG CORELIQUID S360

**RAM**: 64GB G.Skill Trident Z5 RGB DDR5 6400MHz

- F5-6400J3239F32GX2-TZ5RS
- Timing 32-39-39-102

**GPU**: Intel Arc B580

**Power**: CORSAIR RM1200x Shift ATX 3.0 PCIe 5.0 80 PLUS Gold

**Storage (OS)**: Crucial T705 PCIe 5.0 NVMe SSD TLC NAND

- CT2000T705SSD3
- Sequential read/write: 14,500/12,700 MB/s

**Storage (scratch / high-speed local)**: Corsair MP700 PRO SE Hydro X Series PCIe 5.0 NVMe SSD TLC NAND

- CSSD-F2000GBMP700PHXS
- Sequential read/write: 14,000/12,000 MB/s

**Networking**: 10 GbE motherboard NIC

**Case**: Fractal North

**UPS**: Ubiquiti UniFi UPS 2U

**Fleet role notes**:

- Den role: `compute-node`.
- Operating system: currently Pop!_OS bare metal; planned target is CachyOS unless a migration spike finds a concrete blocker.
- Virtualization role: default CPU-heavy VM/MicroVM host.
- GPU role: Intel Arc host for media/transcoding/experiments, not primary AI serving.
- Good fit: build farm jobs, ephemeral QEMU MicroVM runners, CPU-heavy lab VMs, databases that need fast temporary local NVMe, non-critical Intel Arc experiments.
- Avoid scheduling GPU-critical services here when `svc` is available.

## Local AI (`nixos-hermes`)

Always-on assistant node. This machine should remain operationally conservative: it runs Hermes and supporting local services, not the noisy lab workload pool.

2024 HP Elite Mini 800 G9

**CPU**: Intel Core i5-14500T

**RAM**: 96GB Crucial DDR5 5600MHz SODIMM

- CT2K48G56C46S5
- Timing 46-45-45

**GPU**: UHD Graphics 770

**Storage (OS)**: Samsung 990 Pro PCIe 4.0 NVMe SSD DRAM TLC V-NAND

- MZ-V9P2T0B/AM (x2)
- Sequential read/write: 7,450/6,900 MB/s

**Networking**: 1 GbE motherboard NIC

**Fleet role notes**:

- Den role: `assistant-node` / `control-plane-lite`.
- Virtualization role: minimal; use for Hermes-adjacent test runners only when needed.
- GPU role: none for serious AI workloads.
- Good fit: Hermes Agent, small local inference, orchestration, monitoring clients, lightweight control-plane services.
- Avoid moving heavy virtualization here. This node's value is availability, not brute force.

## Personal (`rzp-mac-mini`)

Personal workstation. This is part of the fleet inventory but not a general lab workload host.

2024 Mac Mini

**CPU**: M4 10-core

**RAM**: 16GB unified memory

**GPU**: M4 10-core

**Storage**: 256GB NVMe SSD

**Networking**: 10 GbE

**Fleet role notes**:

- Den role: `workstation` / `darwin-client`.
- Virtualization role: local personal/dev only.
- Good fit: Darwin/home-manager configuration, interactive development, fleet access.
- Avoid coupling core lab services to the workstation.

## Host-Agnostic Infrastructure

### Networking

Internet connection: 2 Gbps fiber.

Network hardware:

- UCG-Fiber (30W) x1
- USW-Pro-XG-8-PoE (155W) x1
- U7-Pro-XG x2
- USW-Aggregation x1
- USW-Flex-2.5G-5 x2
- USW-Flex-Mini x3
- U6-Enterprise-IW x1

## Placement Policy

The fleet uses role-based placement rather than host-by-host vibes.

| Workload shape | Default placement | Reason |
|---|---|---|
| NVIDIA GPU inference/training | `svc` | RTX 4080 is the only serious GPU listed. |
| CPU-heavy virtualization | `rzp-hpc` first, `svc` second | Strong CPUs; keeps GPU node capacity available when possible. Gaming sessions may preempt `rzp-hpc`. |
| Ephemeral QEMU MicroVM tests | `rzp-hpc` or `svc` | These hosts can absorb noisy rootful test workloads. |
| Durable storage services | `nas` | Storage authority and large disk pool. |
| Backup targets / media data | `nas` | Capacity and persistence. |
| Hermes / assistant control plane | `nixos-hermes` | Availability and isolation from noisy lab workloads. |
| Ordinary app containers | `svc`, `rzp-hpc`, or `nas` if storage-adjacent | Use OCI unless the service deserves an OS boundary. |
| Full NixOS appliance guests | `svc` or `rzp-hpc` | Model as Den hosts embedded into a virtualization host. |

## Den Modeling Sketch

The hardware facts become host metadata. Behavior still lives in aspects.

```nix
den.hosts.x86_64-linux.svc = {
  site = "home";
  environment = "prod";
  role = "compute-node";
  hardware.cpu.class = "high-performance";
  hardware.gpu = {
    vendor = "nvidia";
    model = "rtx-4080-super";
    vramGB = 16;
    primary = true;
  };
  hardware.network.primarySpeed = "10g";
  virtualization.heavy = true;
};

den.hosts.x86_64-linux.rzp-hpc = {
  site = "home";
  environment = "prod";
  role = "compute-node";
  os.family = "linux";
  os.distribution = "cachyos";
  os.currentDistribution = "pop-os";
  os.management = "system-manager";
  interactive.gaming = true;
  hardware.cpu.class = "high-performance";
  hardware.gpu = {
    vendor = "intel";
    model = "arc-b580";
    primary = false;
  };
  hardware.network.primarySpeed = "10g";
  virtualization.heavy = true;
};

den.hosts.x86_64-linux.nas = {
  site = "home";
  environment = "prod";
  role = "storage-node";
  os.family = "linux";
  os.distribution = "unraid";
  os.management = "appliance";
  hardware.storage.authority = true;
  hardware.storage.mixedSizeArray = true;
  hardware.network.primarySpeed = "10g";
};

den.hosts.x86_64-linux.nixos-hermes = {
  site = "home";
  environment = "prod";
  role = "assistant-node";
  hardware.network.primarySpeed = "1g";
  virtualization.heavy = false;
};
```

Concrete host aspects stay thin:

```nix
den.aspects.svc.includes = [
  lab.roles.compute-node
  lab.features.virtualization-host
  lab.features.nvidia-gpu
  lab.features.microvm-runner
];

den.aspects.rzp-hpc.includes = [
  lab.roles.compute-node
  lab.features.external-linux-agent
  lab.features.virtualization-capable
  lab.features.intel-arc
  lab.features.steam-gaming-host
  lab.features.microvm-runner
];

den.aspects.nas.includes = [
  lab.roles.storage-node
  lab.features.unraid-appliance
  lab.features.storage-authority
  lab.features.backup-target
];

den.aspects.nixos-hermes.includes = [
  lab.roles.assistant-node
  lab.workloads.hermes-agent
];
```

## Non-NixOS Management Boundary

Declarative infrastructure does not require every physical host to run NixOS. The fleet model separates **inventory and intent**, which Den owns, from **host configuration authority**, which varies by OS.

| OS / platform shape | Declarative authority | Management pattern |
|---|---|---|
| NixOS | Full system graph | Den renders NixOS modules and deploys with rebuild tooling. |
| nix-darwin | Full user/system graph within Darwin limits | Den renders Darwin/Home Manager outputs. |
| Unraid appliance | Inventory, exported services, shares, backup policy, monitoring | Den records desired topology; an `unraid` integration applies supported API/CLI/config changes and treats the rest as audited drift. |
| Pop!_OS / CachyOS / other mutable Linux | Inventory, Nix-managed system packages/services where supported, workload placement, monitoring | Den renders a System Manager config where viable; otherwise it falls back to Ansible, deploy-rs scripts, systemd unit templates, Home Manager-on-Linux, or bespoke SSH actions. |
| Third-party firmware/appliance | Inventory and integration contracts | Den owns DNS, monitoring, backups, credentials, and documented manual edges. |

The rule is: **non-NixOS hosts are still Den hosts, but they are not `nixos` class outputs.** They use classes such as `externalLinux`, `unraid`, `monitoring`, `dns`, `backup`, or `docs` instead of pretending they can consume NixOS modules.

This keeps the infra-as-code foundation honest. NixOS remains the gold standard for full declarative control, but the model does not lie about appliances or gaming distros. Where a platform cannot be fully converged declaratively, Den records the desired state, generates the parts that are automatable, and marks the rest as an explicit manual or audited boundary.

## Hermes Remote Execution Policy

The `svc` host is the right candidate for heavyweight Hermes terminal execution once it is online and reachable over SSH. The assistant state remains on `nixos-hermes`, but the terminal/file/code execution backend can run commands on `svc` through Hermes' SSH terminal backend.

Recommended split:

| Work shape | Execution host | Rationale |
|---|---|---|
| Hermes gateway, memory, sessions, Discord/API adapters | `nixos-hermes` | Keep always-on assistant state stable and local. |
| Heavy builds, tests, VM/MicroVM experiments, GPU probes | `svc` via SSH backend | Use the 14900K, 192GB RAM, RTX 4080, and fast NVMe. |
| Direct edits to the `nixos-hermes` host config | `nixos-hermes` until remote checkout policy is settled | Avoid path/sync surprises in the GitButler repo. |
| One-off commands against other hosts | Explicit SSH from the active backend | Do not make the global Hermes terminal hop unpredictably. |

Hermes' SSH backend syncs selected files to the remote and executes terminal/file operations there. That is useful for compute, but it changes path semantics: `/var/lib/hermes/workspace/nixos-hermes` on `nixos-hermes` is not automatically the same checkout on `svc`. Before making SSH the default backend, provision a matching remote workspace, SSH key, host key trust, GitHub auth policy, `but`, Nix tooling, and a rollback path to local execution.

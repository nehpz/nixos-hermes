# First Install

Two paths are supported. **Prefer nixos-anywhere** for a headless host: you never need to touch a keyboard on the target. Fall back to the Live CD flow  only when SSH to the target is not available (no IPMI, no rescue OS).

## Path A: nixos-anywhere (recommended, headless)

### What nixos-anywhere needs

Exactly one thing: SSH access to the target as `root` (or as a user with  passwordless `sudo`), running any reasonably current Linux kernel. From there it kexecs into a NixOS installer, partitions via `disk-config.nix`, installs the flake, and reboots — without you touching the physical machine again.

The age private key is seeded onto the target during install via `--extra-files`, so sops-nix can decrypt secrets on first activation.

### Getting the target to an SSH-reachable Linux state

The prep required depends on the target's starting state.

#### State 1 — target is already running a Linux distro (Ubuntu, Debian, Fedora, etc.).

This is the easiest path; nothing to install. Just confirm:

- `sshd` is running and reachable from your workstation.
- Your workstation's public key is in `~/.ssh/authorized_keys` for either `root` or a user with passwordless `sudo`.
- The machine has outbound internet (nixos-anywhere fetches nixpkgs during install).

nixos-anywhere will kexec over the existing distro and wipe the disks per `disk-config.nix`, so there is nothing on the current install worth preserving.

#### State 2 — target is bare-metal with no OS.

Two routes, depending on whether vPro / Intel AMT is provisioned on the host.

*State 2a — USB boot (one-time physical console access):*

1. On your workstation, download the NixOS minimal installer ISO (https://nixos.org/download/#nixos-iso) or the Determinate Nix installer ISO — any standard NixOS live ISO works.
2. Write it to a USB stick (e.g. `dd if=nixos-minimal-*.iso of=/dev/diskN bs=4M`, or use Etcher / Rufus).
3. Plug USB + monitor + keyboard into the target; boot from USB.
4. At the installer prompt, set a temporary root password:

   ```bash
   sudo passwd root
   ```
5. Confirm `sshd` is running (it is, on recent installer ISOs) and find the target's IP:

   ```bash
   ip -4 addr show | grep inet
   ```
6. From your workstation, copy your key in once (using the password from step 4); after this, unplug monitor + keyboard and finish headlessly:

   ```bash
   ssh-copy-id root@<target-ip>
   ```

Alternatively, build a custom installer ISO with your SSH key baked in (`nixos-generators -f iso ...`). For a one-off reprovision, `ssh-copy-id` is faster.

*State 2b — Intel vPro / AMT IDE-R (fully remote after one-time MEBx setup):*

The hermes host (HP Elite Mini 800 G9, appropriate SKU) includes Intel vPro. Once AMT is provisioned in MEBx, there is no further need for a USB stick, monitor, or keyboard on the target — every reprovision is pure-network.

One-time physical setup (only required the first time, or after an AMT reset):

1. Power on the target; press `F6` at POST to enter the Intel ME BIOS Extension (MEBx).
2. Change the default MEBx password, enable AMT, enable remote access, configure the network profile (DHCP is fine on a trusted LAN).
3. Save and exit. Note the AMT IP / hostname and the new MEBx password — store both in your workstation password manager.

Per reprovision (fully remote):

1. On your workstation, install an AMT client: MeshCommander (legacy but reliable), [MeshCentral](https://meshcentral.com/), or [wsman-cli](https://github.com/Openwsman/openwsman). MeshCommander's IDE-R dialog is the most discoverable.
2. Download the NixOS minimal / Determinate Nix installer ISO to the workstation (same file that would otherwise go on the USB stick).
3. Connect to the target's AMT interface (ports 16992–16995) using the MEBx password.
4. Mount the ISO via **Storage Redirection → IDE-R** (or USB-R on AMT ≥ 16). Set one-time boot override to "CD/DVD".
5. Trigger an AMT power-cycle. The target now boots the installer from the workstation-hosted ISO over the network.
6. Open the AMT **KVM** (VNC-over-AMT) or **Serial-over-LAN** session to reach the installer's shell — same steps 4–6 as State 2a (set root password, `ip addr`, `ssh-copy-id` from workstation).
7. Close the AMT session, detach the IDE-R media, and run `nixos-anywhere` as  normal.

Caveats:

- IDE-R ISO size limits depend on AMT firmware; ISOs < 4 GB work on essentially all AMT versions, which covers both NixOS minimal and Determinate Nix.
- AMT ports 16992–16995 must be reachable from your workstation. Some corporate networks block them; confirm before committing to this route.
- AMT KVM is hardware-accelerated video redirection, not an SSH-like terminal. Type the key-authorization commands carefully; there is no copy-paste unless your client supports it.

#### State 3 — target has IPMI/iDRAC/BMC with remote media.

Not applicable to the hermes host (HP Elite Mini has no dedicated BMC; vPro/AMT is the closest equivalent and is covered in State 2b). For other deployments: mount a Linux rescue ISO (SystemRescue, Ubuntu Live, or the NixOS minimal installer) via the BMC web UI, then authorize your SSH key as in state 2a.

### Workstation prerequisites

On the machine running `nix run .#nixos-anywhere`:

- A clone of this repo with the flake `flake.lock` committed.
- The age private key for this host available at some local path.
- An SSH agent or key that authenticates against whatever you set up on the target above.
- Outbound SSH to the target on port 22 (nixos-anywhere uses SSH only).

### Run the install

Run from your workstation checkout of this repo:

```bash
# 1. Stage the age key at the exact layout it must land in on the target.
#    Everything under extra-files/ is rsync'd to / on the installed system.
mkdir -p extra-files/etc/secrets
cp /path/to/age.key extra-files/etc/secrets/age.key
chmod 400 extra-files/etc/secrets/age.key

# 2. Kexec the target (if not already NixOS) into the NixOS installer, run
#    disko from hosts/hermes/disk-config.nix, install, and reboot.
nix run .#nixos-anywhere -- \
  --flake .#nixos-hermes \
  --extra-files extra-files \
  root@<target-ip-or-host>

# 3. Securely wipe and remove the plaintext age key staging dir. Plain `rm`
#    leaves the key recoverable on many filesystems; shred overwrites first.
#    extra-files/ is gitignored but must not linger as recoverable plaintext.
find extra-files -type f -exec shred -u {} +
rm -rf extra-files
```

After the first successful install, subsequent changes use the normal `Apply
to Host` flow below — nixos-anywhere is only for bootstrapping or re-imaging.

## Path B: Live CD / manual nixos-install (fallback)

Use this only when you cannot SSH into the target before install. Boot the
NixOS installer ISO on the target and run:

```bash
# 1. Place the age private key on the live environment.
mkdir -p /etc/secrets
cp /path/to/age.key /etc/secrets/age.key

# 2. Clone the repo.
nix shell nixpkgs#git -c git clone https://github.com/nehpz/nixos-hermes /root/nixos-hermes
cd /root/nixos-hermes

# 3. Partition, format, and mount every filesystem under /mnt in one shot.
# disko reads disk-config.nix, destroys existing layouts on the target disks,
# creates GPT + ESPs + zpool + datasets, and mounts everything at /mnt
# according to the mountpoint attributes. `.#disko` uses the lockfile-pinned
# disko, matching the version the NixOS module was evaluated against.
nix run .#disko -- --mode disko hosts/hermes/disk-config.nix

# 4. Pre-place the age key inside the target root so sops-nix can decrypt
# secrets during first activation.
mkdir -p /mnt/etc/secrets
cp /etc/secrets/age.key /mnt/etc/secrets/age.key

# 5. Install. Everything else (hostname, users, services, bootloader) is
# declarative.
nixos-install --flake github:nehpz/nixos-hermes#nixos-hermes \
  --option extra-substituters https://cache.flakehub.com \
  --option extra-trusted-public-keys 'cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM='

# 6. Sanity-check that the bootloader was written to the ESP.
ls /mnt/boot/nixos/
```

The `extra-substituters` flags are only required for the initial install. Once Determinate Nix v3.6.0 or later is running on the host, subsequent `nixos-rebuild` runs need no extra options.

**If `nixos-install` fails at the bootloader step** with an empty or missing `/boot`, apply the manual bootloader install below. This has historically been needed on this host because NixOS activation can remove the `/boot` mountpoint from the ZFS root before `bootctl install` runs. Option 2 (disko as a NixOS module) may have fixed the root cause; test a clean install before assuming the workaround is still required.

```bash
# Re-mount the ESP and enter a chroot that bypasses nixos-enter's activation.
mkdir -p /mnt/boot
mount /dev/disk/by-partlabel/disk-nvme0-ESP /mnt/boot
mount --bind /proc /mnt/proc
mount --bind /dev  /mnt/dev
mount --bind /sys  /mnt/sys
mount -t tmpfs none /mnt/run

NIXOS_INSTALL_BOOTLOADER=1 \
  chroot /mnt /nix/var/nix/profiles/system/bin/switch-to-configuration boot

ls /mnt/boot/nixos/    # must contain files
```

## Apply to Host

```bash
# Build and activate on the host directly:
ssh admin@nixos-hermes 'sudo nixos-rebuild switch --flake github:nehpz/nixos-hermes#nixos-hermes'

# Or push from local checkout:
nixos-rebuild switch --flake .#nixos-hermes \
  --target-host admin@nixos-hermes \
  --build-host  admin@nixos-hermes \
  --use-remote-sudo
```

CI publishes the flake to FlakeHub on every push to `main`. There is no automated deploy; all applies are manual.

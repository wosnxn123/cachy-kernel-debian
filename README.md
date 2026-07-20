<div style="border: 3px solid #6effaf; border-radius: 5px; overflow: hidden; display: inline-block;">
  <img src="assets/cachydebian.png" alt="CachyOS Debian kernel builder" style="display: block;">
</div>

# CachyOS Kernel Debian Builder

[中文文档](README.zh-CN.md) | English

This repository builds selected [CachyOS](https://github.com/CachyOS/linux-cachyos) Linux kernel variants as installable Debian `.deb` packages.

It is for Debian-based systems where you want a CachyOS-flavored kernel without keeping a full local build toolchain. Desktop and server installs are both in scope.

This project is not affiliated with CachyOS. Kernel sources and packaging metadata are fetched from upstream CachyOS repositories at build time.

Primary compile path: **CNB Cloud Native Build** (32 vCPU), triggered and reported by GitHub Actions. GitHub/Blacksmith is a manual fallback.

Based on [Deadly-Signal/cachy-kernel-debian](https://github.com/Deadly-Signal/cachy-kernel-debian).

## Quick start

### Install an existing build

1. Open [Releases](../../releases).
2. Download matching `linux-image-*.deb` and `linux-headers-*.deb`.
3. Prefer ordinary image/headers packages. Skip `*-dbg` unless you need crash debugging.
4. Install:

```bash
sudo apt install ./linux-image-*.deb ./linux-headers-*.deb
sudo update-grub
sudo reboot
uname -r
```

If the Release also ships `linux-libc-dev_*.deb` and you want matching userspace headers, install it too.

Keep a known-good distribution kernel installed so the bootloader can fall back.

### Build a new package

1. Open **Actions**
2. Run **Build CachyOS Kernel on CNB**
3. Choose the inputs you need
4. After success, download from:
   - GitHub **Release** (when `publish_release=true`)
   - the workflow run **Artifacts** (14-day retention)

## Workflows

| Workflow | Purpose | When it runs |
| --- | --- | --- |
| **Build CachyOS Kernel on CNB** | Main build path. One combination per run. | Manual |
| **Check and build aggressive x64v2 on CNB** | Check latest `linux-cachyos-rc` + `generic_v2`; build only if that Release is missing | Schedule + manual |
| **Build Custom CachyOS Kernel Debian Package** | GitHub/Blacksmith single-combination fallback | Manual |
| **Reusable CachyOS Kernel Build** | Internal reusable job for the custom fallback | Not user-facing |

## What it builds

Each run roughly:

1. Reads the selected official CachyOS packaging variant from [CachyOS/linux-cachyos](https://github.com/CachyOS/linux-cachyos)
2. Runs that variant’s upstream `PKGBUILD` `prepare()` so patches and profile come from upstream
3. Applies this repository’s post-prepare compatibility pass (currently `server-kvm`)
4. Compiles with the selected x86-64 baseline (`x64v1` / `x64v2` / `x64v3`)
5. Packages with `bindeb-pkg`
6. Validates packages and optionally boots the image in QEMU
7. Publishes outputs

Typical packages:

- `linux-image-*.deb`
- `linux-headers-*.deb`
- `linux-libc-dev_*.deb` when produced
- `BUILD-MANIFEST.txt` with version details and SHA256 sums

`linux-image-*-dbg` is skipped by default because it is huge and usually unnecessary.

### Profile ownership

| Layer | Source |
| --- | --- |
| Scheduler, LTO/compiler, HZ, tick, preemption, THP, O3, governor, BBR3, KCFI | Selected upstream CachyOS variant (`upstream-default`) or an explicit scheduler override |
| Extra Debian/KVM compatibility options | Applied by this repository after upstream prepare |
| CPU baseline marker | Selected `generic` / `generic_v2` / `generic_v3` → visible as `x64v1` / `x64v2` / `x64v3` |

`upstream-default` means “do not override the variant’s own scheduler”. For `linux-cachyos-rc`, that is the official RC default profile.

Stable and RC tracks differ because their upstream profiles differ. Resolved values are recorded in `BUILD-MANIFEST.txt`.

## CPU baselines

| Label | `cpu_target` | Meaning |
| --- | --- | --- |
| `x64v1` | `generic` | Broadest compatibility |
| `x64v2` | `generic_v2` | Needs x86-64-v2 features such as SSSE3, SSE4.1/4.2, POPCNT, CX16, LAHF/SAHF |
| `x64v3` | `generic_v3` | Needs x86-64-v3 features such as AVX2, BMI1/2, FMA, MOVBE, F16C |

These labels are instruction-set floors, not CPU model names. Check the target machine before installing:

```bash
lscpu
```

CI does **not** use `-march=native`. A runner-native build would optimize for the cloud runner, not your machine.

Example: an Ivy Bridge-class guest such as Xeon E5-2696 v2 is typically a good fit for **`x64v2`**, not `x64v3`.

## Manual CNB build inputs

| Input | Default | Notes |
| --- | --- | --- |
| `kernel_variant` | `linux-cachyos-rc` | Official packaging variant |
| `cpu_target` | `generic_v2` | `generic` / `generic_v2` / `generic_v3` |
| `cpu_scheduler` | `upstream-default` | Or explicit override: `cachyos`, `eevdf`, `bore`, `bmq`, `hardened`, `rt`, `rt-bore` |
| `run_qemu_smoke_test` | `true` | Minimal QEMU boot check |
| `publish_release` | `true` | Create/update a normal GitHub Release |
| `release_tag` | empty | Blank = auto tag such as `cachyos-debian-aggressive-7.2.rc3-2-x64v2` |
| `mark_latest` | `false` | Whether to mark the Release as latest |
| `skip_debug_packages` | `true` | Skip giant `*-dbg` packages |

## Automatic aggressive x64v2 check

Workflow: **Check and build aggressive x64v2 on CNB**

Optional automation for one common combination:

- variant: `linux-cachyos-rc`
- CPU: `generic_v2` (`x64v2`)
- scheduler: `upstream-default`
- publish Release: on
- skip `-dbg`: on by default

Logic:

1. Runs on a daily schedule at **00:00 UTC (08:00 Asia/Shanghai)**
2. Clones upstream RC packaging metadata
3. Computes the expected Release tag
4. Builds on CNB only if that Release does **not** already exist
5. Manual runs perform the same check immediately

If writing the Actions variable `CNB_AGGRESSIVE_V2_LAST_CHECK` is forbidden by repository token policy, the workflow warns and continues. The real build gate is still “does the Release already exist?”

To force a rebuild even when the Release exists, use **Build CachyOS Kernel on CNB** directly.

## Outputs: Release and Artifacts

Successful CNB builds provide:

1. **GitHub Release** when `publish_release=true`
2. **GitHub Actions Artifacts** on the same workflow run (14 days)

How Artifacts are produced:

1. CNB uploads packages to a temporary draft release named `cnb-run-<github_run_id>`
2. The GitHub job downloads that draft
3. The job uploads workflow Artifacts
4. The temporary draft is deleted best-effort

Download from the normal Release or the workflow Artifacts page. Ignore temporary `cnb-run-*` drafts if you ever notice one mid-run.

## Install and rollback

```bash
sudo apt install ./linux-image-*.deb ./linux-headers-*.deb
sudo update-grub
sudo reboot
uname -r
```

Before installing, inspect `BUILD-MANIFEST.txt` for version, CPU baseline, scheduler, and checksums.

Keep a known-good stock kernel installed so the bootloader can recover if the custom kernel misbehaves.

## CNB setup for forks

Default CNB repository path:

```text
<your-github-owner>/cachy-kernel-debian
```

Override with Actions variable `CNB_REPO` when needed.

Setup:

1. Create an empty CNB repository
2. Create a CNB access token with repository write access and `repo-cnb-trigger:rw`
3. In GitHub: **Settings → Secrets and variables → Actions**
   - Secret `CNB_TOKEN` = CNB token
   - Optional variable `CNB_REPO` = `org/repo`
4. Ensure GitHub Actions can write repository contents (`contents: write` is already requested)
5. Run **Build CachyOS Kernel on CNB**

### Trust boundary

| Item | Who holds it |
| --- | --- |
| `CNB_TOKEN` | GitHub Actions secret only |
| Temporary `GITHUB_TOKEN` | Injected into one CNB job for Release/Artifact upload, then expires |
| Permanent GitHub credentials in CNB | Not stored |

CNB does not get permission to push Git commits back to GitHub. GitHub force-syncs the exact commit being built to the CNB repo before dispatch.

Docs:

- [StartBuild API](https://api.cnb.cool/#/operations/StartBuild)
- [CNB build nodes](https://docs.cnb.cool/en/build/build-node.html)

## GitHub / Blacksmith fallback

If CNB is unavailable, use **Build Custom CachyOS Kernel Debian Package**.

- Builds one combination only
- Can use Blacksmith or `ubuntu-24.04`
- Uploads workflow Artifacts
- Can optionally publish a Release

## Compatibility notes

After upstream prepare, this repository applies a Debian/KVM-friendly compatibility pass. It keeps common boot and module options enabled, for example:

- initramfs boot
- loadable modules
- VirtIO / KVM / common block and net drivers
- common filesystems and networking features including WireGuard

Whether a package works well still depends on hardware, firmware, bootloader, Secure Boot, DKMS modules, and the distro release.

VirtIO-GPU is optional. Headless guests usually do not need it.

## Validation

Before publish, the build:

- checks that image/header packages exist
- inspects `.deb` metadata
- runs `lintian` with expected kernel-package allowlists
- checks for `vmlinuz-*`, modules, and headers content
- optionally boots the kernel in QEMU until a serial success marker appears

Lintian `W:` warnings for long package names or header helper binaries are expected for custom kernels.

## Repository layout

```text
.cnb.yml
.cnb/Dockerfile
.cnb/build-kernel.sh
.github/workflows/build-cachyos-kernel-cnb.yml
.github/workflows/build-cachyos-kernel-cnb-aggressive-v2.yml
.github/workflows/build-cachyos-kernel-custom.yml
.github/workflows/reusable-cachyos-kernel-build.yml
README.md
README.zh-CN.md
```

## Important notes

- Kernel fitness depends on your hardware, firmware, bootloader, Secure Boot policy, DKMS modules, and distro release
- Secure Boot environments may require signing or policy changes
- Out-of-tree modules such as NVIDIA DKMS are not built here
- Always verify CPU baseline before installing an `x64vN` package
- Packages are ordinary Debian kernel packages; they are not Proxmox-flavored kernels and not Ubuntu HWE packages

## Links

- [中文文档](README.zh-CN.md)
- [Deadly-Signal/cachy-kernel-debian](https://github.com/Deadly-Signal/cachy-kernel-debian)
- [CachyOS packaging](https://github.com/CachyOS/linux-cachyos)
- [CachyOS kernel sources](https://github.com/CachyOS/linux/releases)
- [CNB StartBuild API](https://api.cnb.cool/#/operations/StartBuild)

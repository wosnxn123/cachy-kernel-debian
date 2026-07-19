<div style="border: 3px solid #6effaf; border-radius: 5px; overflow: hidden; display: inline-block;">
  <img src="assets/cachydebian.png" alt="CachyOS Debian kernel builder" style="display: block;">
</div>

# CachyOS Kernel Debian Builder

[中文文档](README.zh-CN.md) | English

Build selected [CachyOS](https://github.com/CachyOS/linux-cachyos) kernel variants as Debian `.deb` packages for **headless Debian/KVM servers**.

This is **not** an official CachyOS project. It repackages upstream CachyOS sources at build time and adds a fixed Debian server/KVM compatibility layer.

Primary compile path: **CNB Cloud Native Build** (32 vCPU), scheduled and reported by GitHub Actions.

## Quick Start

### Install an existing build

1. Open [Releases](../../releases).
2. Download the matching `linux-image-*.deb` and `linux-headers-*.deb`.
3. Prefer ordinary image/headers packages. Skip `*-dbg` unless you need crash debugging.
4. Install:

```bash
sudo apt install ./linux-image-*.deb ./linux-headers-*.deb
sudo update-grub
sudo reboot
uname -r
```

Keep a known-good Debian kernel as a GRUB fallback.

### Build a new package

1. Open **Actions**
2. Run **Build CachyOS Kernel on CNB**
3. Recommended defaults for a modern-enough x86-64-v2 KVM guest:

| Input | Recommended value |
| --- | --- |
| `kernel_variant` | `linux-cachyos-rc` |
| `cpu_target` | `generic_v2` |
| `cpu_scheduler` | `upstream-default` |
| `run_qemu_smoke_test` | `true` |
| `publish_release` | `true` |
| `skip_debug_packages` | `true` |
| `mark_latest` | `false` |

4. After success, download from:
   - GitHub **Release** (long-term)
   - the workflow run **Artifacts** (14-day retention)

## Workflows

| Workflow | Purpose | When it runs |
| --- | --- | --- |
| **Build CachyOS Kernel on CNB** | Main build path. One combination per run. | Manual |
| **Check and build aggressive x64v2 on CNB** | Auto-check latest `linux-cachyos-rc` + `generic_v2`. Builds only if that Release is missing. | Schedule + manual |
| **Build Custom CachyOS Kernel Debian Package** | GitHub/Blacksmith single-combination fallback | Manual |
| **Reusable CachyOS Kernel Build** | Internal reusable job used by the custom fallback | Not user-facing |

The old “build many kernels in one click” multi-matrix entry is removed.

## What Gets Built

Each run:

1. Reads the selected official CachyOS packaging variant from [CachyOS/linux-cachyos](https://github.com/CachyOS/linux-cachyos)
2. Runs that variant’s upstream `PKGBUILD` `prepare()` so patches/profile come from upstream
3. Applies this repository’s fixed **Debian server/KVM** config pass
4. Compiles with the selected x86-64 baseline (`x64v1` / `x64v2` / `x64v3`)
5. Packages with `bindeb-pkg`
6. Validates packages and optionally boots the image in QEMU
7. Publishes outputs

Typical packages:

- `linux-image-*.deb`
- `linux-headers-*.deb`
- `linux-libc-dev_*.deb` when produced
- `BUILD-MANIFEST.txt` with version details and SHA256 sums

`linux-image-*-dbg` is skipped by default because it is huge and usually unnecessary on servers.

### Profile ownership

| Layer | Source |
| --- | --- |
| Scheduler, LTO/compiler, HZ, tick, preemption, THP, O3, governor, BBR3, KCFI | Selected upstream CachyOS variant (`upstream-default`) or explicit scheduler override |
| Debian/KVM server compatibility | Fixed by this repository after upstream prepare |
| CPU baseline marker | Selected `generic` / `generic_v2` / `generic_v3` → visible as `x64v1` / `x64v2` / `x64v3` |

`upstream-default` means “do not override the variant’s own scheduler.” For `linux-cachyos-rc` that is the official RC default (commonly the CachyOS scheduler profile).

Stable and RC tracks intentionally differ because their upstream profiles differ. This repository does not hard-code a permanent “stable vs RC feature matrix”; it follows the selected official variant and records the resolved values in `BUILD-MANIFEST.txt`.

## CPU Baselines

| Label | `cpu_target` | Meaning |
| --- | --- | --- |
| `x64v1` | `generic` | Broadest compatibility |
| `x64v2` | `generic_v2` | Needs x86-64-v2 features such as SSSE3, SSE4.1/4.2, POPCNT, CX16, LAHF/SAHF |
| `x64v3` | `generic_v3` | Needs x86-64-v3 features such as AVX2, BMI1/2, FMA, MOVBE, F16C |

These labels are **instruction-set floors**, not CPU model names. Check the target machine before installing:

```bash
lscpu
```

This project does **not** use `-march=native` in CI. Runner-native builds would optimize for the cloud runner, not your server.

Example: an Ivy Bridge-class guest such as Xeon E5-2696 v2 is typically a good fit for **`x64v2`**, not `x64v3`.

## Manual CNB Build Inputs

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

## Automatic Aggressive x64v2 Check

Workflow: **Check and build aggressive x64v2 on CNB**

Fixed build target when a build is needed:

- variant: `linux-cachyos-rc`
- CPU: `generic_v2` (`x64v2`)
- scheduler: `upstream-default`
- config: Debian server/KVM
- QEMU smoke test: on
- publish Release: on
- skip `-dbg`: on by default

Logic:

1. Scheduled daily timer only checks whether ten days have passed since the last recorded check
2. When due, clone upstream RC packaging metadata
3. Compute the expected Release tag
4. Build on CNB only if that Release does **not** already exist
5. Manual runs always perform the upstream check immediately

If writing the Actions variable `CNB_AGGRESSIVE_V2_LAST_CHECK` is forbidden by repository token policy, the workflow warns and continues. The real build gate is still “does the Release already exist?”

If you want a rebuild even when the Release exists, use **Build CachyOS Kernel on CNB** directly.

## Outputs: Release and Artifacts

Successful CNB builds provide:

1. **GitHub Release** when `publish_release=true`
2. **GitHub Actions Artifacts** on the same workflow run (14 days)

How Artifacts are produced:

1. CNB uploads packages to a temporary draft release named `cnb-run-<github_run_id>`
2. The GitHub job downloads that draft
3. The job uploads workflow Artifacts
4. The temporary draft is deleted

End users should download from the normal Release or the workflow Artifacts page. Ignore temporary `cnb-run-*` drafts if you ever notice one mid-run.

CNB itself does not need a permanent “attachments” UI for this flow.

## Install and Rollback

```bash
sudo apt install ./linux-image-*.deb ./linux-headers-*.deb
sudo update-grub
sudo reboot
uname -r
```

Before installing, inspect `BUILD-MANIFEST.txt` for version, CPU baseline, scheduler, and checksums.

Always keep a known-good stock Debian kernel installed so GRUB can boot it if the custom kernel misbehaves.

## CNB Setup for Forks

Default CNB repository path:

```text
<your-github-owner>/cachy-kernel-debian
```

This repository may use a different path through the Actions variable `CNB_REPO`.

Setup:

1. Create an empty CNB repository
2. Create a CNB access token with repository write access and `repo-cnb-trigger:rw`
3. In GitHub: **Settings → Secrets and variables → Actions**
   - Secret `CNB_TOKEN` = CNB token
   - Optional variable `CNB_REPO` = `org/repo` if not using the default path
4. Ensure GitHub Actions can write repository contents (this workflow already requests `contents: write`)
5. Run **Build CachyOS Kernel on CNB**

### Trust boundary

| Item | Who holds it |
| --- | --- |
| `CNB_TOKEN` | GitHub Actions secret only |
| Temporary `GITHUB_TOKEN` | Injected into one CNB job for Release/Artifact upload, then expires |
| Permanent GitHub credentials in CNB | Not stored |

CNB does not get permission to push Git commits back to GitHub. GitHub force-syncs the exact commit being built to the CNB repo before dispatch.

The CNB repository may be public or private. Secrets are not stored in that repository.

Docs:

- [StartBuild API](https://api.cnb.cool/#/operations/StartBuild)
- [CNB build nodes](https://docs.cnb.cool/en/build/build-node.html)

## GitHub / Blacksmith Fallback

If CNB is unavailable, use **Build Custom CachyOS Kernel Debian Package**.

- Builds one combination only
- Can use Blacksmith or `ubuntu-24.04`
- Uploads workflow Artifacts
- Can optionally publish a Release

This path is the fallback, not the default.

## Server/KVM Compatibility Notes

After upstream prepare, this repository always applies a Debian server/KVM oriented config pass. It is aimed at headless guests and includes common needs such as:

- initramfs boot
- VirtIO disk/net and serial console
- KVM/VFIO modules
- common filesystems and networking features including WireGuard
- modules useful on generic Debian servers

A VirtIO-GPU device is **not** required for this use case.

## Validation

Before publish, the build:

- checks that image/header packages exist
- inspects `.deb` metadata
- runs `lintian` with expected kernel-package allowlists
- checks for `vmlinuz-*`, modules, and headers content
- optionally boots the kernel in QEMU until a serial success marker appears

Lintian `W:` warnings for long package names or header helper binaries are expected for custom kernels.

## Repository Layout

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

## Important Notes

- Not affiliated with or endorsed by CachyOS
- Kernel fitness depends on your hardware, firmware, bootloader, Secure Boot policy, DKMS modules, and Debian release
- Secure Boot environments may require signing or policy changes
- Out-of-tree modules such as NVIDIA DKMS are not built here
- Always verify CPU baseline before installing an `x64vN` package

## Links

- [中文文档](README.zh-CN.md)
- [CachyOS packaging](https://github.com/CachyOS/linux-cachyos)
- [CachyOS kernel sources](https://github.com/CachyOS/linux/releases)
- [CNB StartBuild API](https://api.cnb.cool/#/operations/StartBuild)

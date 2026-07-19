<div style="border: 3px solid #6effaf; border-radius: 5px; overflow: hidden; display: inline-block;">
  <img src="assets/cachydebian.png" alt="image" style="display: block;">
</div>

# CachyOS Kernel Debian Builder

中文文档：[README.zh-CN.md](README.zh-CN.md) | English

This repository builds selected CachyOS Linux variants as installable Debian
packages for 64-bit Debian server workloads. Compilation runs on CNB Cloud
Native Build on CNB Cloud Native Build.

The target is a headless Debian/KVM server. The packages include initramfs,
VirtIO, serial console, networking, storage, KVM, WireGuard, and common
filesystems; a VirtIO-GPU device is not required.

## What It Builds

The workflow fetches the newest kernel metadata from the official
[CachyOS/linux-cachyos](https://github.com/CachyOS/linux-cachyos) packaging
repository, downloads the matching CachyOS kernel source tarball, compiles the
kernel, and packages the result with the kernel's upstream Debian packaging
target. The official
`PKGBUILD` `prepare()` function applies the upstream patches and profile first;
the Debian/KVM requirements and visible CPU-baseline suffix are added afterward.
Preparation uses the upstream release profile rather than its CI-only
size-optimization fallback, so an upstream `cc_harder=yes` remains O3. The
repository then applies its fixed Debian server/KVM compatibility pass.

Each manual run builds one selected combination. The UI includes the official
default, server, RC, LTS, EEVDF, BORE, BMQ, hardened, RT-BORE, and Deckify
variants, x86-64-v1/v2/v3 baselines, and an upstream-default or explicit
scheduler choice.

The stable track follows the upstream server profile, while the RC track follows
the upstream CachyOS RC profile. Scheduler, CachyOS config, LTO/compiler mode,
timer frequency, tick mode, preemption, THP, O3, governor, BBR3, and KCFI values
are resolved from the selected upstream `PKGBUILD`. The resolved values are
recorded in the Release and `BUILD-MANIFEST.txt`.

The kernel localversion and package/release names contain `x64v1`, `x64v2`, or
`x64v3`, so the required CPU baseline is visible in `uname -r`, package names,
Release names, artifacts, and `BUILD-MANIFEST.txt`.

Expected output includes standard `.deb` packages such as:

- `linux-image-*.deb`
- `linux-headers-*.deb`
- related generated kernel packages produced by `make bindeb-pkg`
- `BUILD-MANIFEST.txt` with source/version details and SHA256 checksums

## Workflow Trigger

Manual builds primarily run through **Build CachyOS Kernel on CNB** and always
build one selected combination. A single-combination GitHub/Blacksmith fallback
remains available as **Build Custom CachyOS Kernel Debian Package**. The old
six-at-once multi-matrix dispatch path is no longer offered.

**Check and build aggressive x64v2 on CNB** is the only automatic workflow. It
checks the upstream RC package once every ten days and builds only when the
latest `aggressive / generic_v2` version has no matching Release.

## Manual Usage

1. Open the repository on GitHub.
2. Go to **Actions**.
3. Select **Build CachyOS Kernel on CNB**.
4. Click **Run workflow**.
5. Choose the desired inputs:
   - `kernel_variant`: official CachyOS packaging variant.
   - `cpu_target`: `generic`, `generic_v2`, or `generic_v3`.
   - `cpu_scheduler`: `upstream-default` or an explicit scheduler override.
   - `run_qemu_smoke_test`: whether to boot-test the built kernel in QEMU.
   - `publish_release`: whether to upload the final packages to a GitHub
     Release.
   - `skip_debug_packages`: skip `linux-image-*-dbg` packages. Default is
     enabled because the dbg package is huge and mostly useful for crash
     debugging.
   - `mark_latest`: whether the Release should be marked as the latest.
6. Wait for the build to finish.
7. Download the generated `.deb` files from the matching GitHub Release.

Use `linux-cachyos-rc`, `generic_v2`, and `upstream-default` for the current
headless Ivy Bridge-class KVM guest. `upstream-default` preserves the selected
official variant's profile; scheduler overrides are for advanced testing.

## CNB Cloud Native Build

**Build CachyOS Kernel on CNB** keeps GitHub Actions as the control plane while
moving compilation to CNB Cloud Native Build.

The bridge works as follows:

1. GitHub pushes the exact workflow commit to the configured CNB repository.
2. GitHub calls CNB's StartBuild API with `api_trigger_kernel`.
3. CNB compiles in a 32-vCPU amd64 container and runs package validation plus
   the optional QEMU boot test.
4. CNB publishes the `.deb` files and `BUILD-MANIFEST.txt` directly to the
   matching GitHub Release.
5. GitHub polls CNB's build-status API and links the CNB log in the job summary.

CNB builds exactly one selected combination per run. This avoids accidental
parallel kernel compiles and keeps CNB core-hour use predictable.

### CNB Setup

1. Create an empty CNB repository. By default, a fork uses
   `<your-GitHub-owner>/cachy-kernel-debian`; create the CNB repository at that
   path, or choose any other CNB `organization/repository` path.
2. Create a CNB access token that can write repository code and has
   `repo-cnb-trigger:rw` permission.
3. In the GitHub fork, open **Settings -> Secrets and variables -> Actions**.
   Create a repository secret named `CNB_TOKEN` and paste the CNB token as its
   value.
4. If the CNB path differs from the default, create an Actions repository
   variable named `CNB_REPO` with the value `organization/repository`.
5. Run **Build CachyOS Kernel on CNB** from the GitHub Actions tab.

CNB does not receive permission to push Git commits. GitHub syncs the workflow
commit to CNB using `CNB_TOKEN`; CNB receives only the current GitHub job token
with `contents: write` permission so it can create a Release and upload `.deb`
assets. That temporary token expires when the dispatcher job ends or is
cancelled, and no permanent GitHub credential is stored in CNB. The CNB path
publishes GitHub Releases and also mirrors packages into the workflow run Artifacts. CNB API details
are documented in [StartBuild](https://api.cnb.cool/#/operations/StartBuild)
and [CNB build nodes](https://docs.cnb.cool/en/build/build-node.html).

### Ten-day aggressive x64v2 check

The scheduled workflow is tailored to this repository's target server:
`linux-cachyos-rc`, `generic_v2` (`x64v2`), and `upstream-default`, and defaults
to skipping `-dbg`. Manual runs of this workflow expose the same
`skip_debug_packages` checkbox. GitHub starts
a lightweight daily timer only to compare `CNB_AGGRESSIVE_V2_LAST_CHECK`; it
does not clone upstream or start CNB until ten full days have elapsed. At that
point it checks the current RC `pkgver/pkgrel`, records the timestamp in that
Actions variable, and starts CNB only when the corresponding Release is absent.

## Available Build Inputs

Manual CNB runs choose one combination at a time:

- `kernel_variant`
- `cpu_target` / `x64v1` `x64v2` `x64v3`
- `cpu_scheduler`
- `run_qemu_smoke_test`
- `publish_release`
- `release_tag` (optional; blank auto-generates)
- `skip_debug_packages` (default: skip)
- `mark_latest`

Before installing a package, check the target machine's CPU flags with
`lscpu`. A machine that lacks the required feature set must not boot that
baseline. `x64v2` is not a CPU model name; it is a minimum instruction-set
level, and `x64v3` is a stricter level intended for newer machines.

The stable and RC tracks intentionally differ because they follow their
respective upstream profiles. At the time of writing, Stable uses EEVDF, GCC
without LTO, 300 Hz, full tickless, lazy preemption, and THP always. RC uses the
CachyOS scheduler, Clang ThinLTO, 1000 Hz, full tickless, full preemption, and
THP always. These are upstream defaults, not permanently hard-coded profiles in
this repository.

### `run_qemu_smoke_test`

When enabled, the workflow extracts the generated kernel image package, creates a
minimal BusyBox initramfs, and boots the kernel with QEMU. The test passes only
if the guest reaches the init process and prints a success marker on the serial
console. The workflow enables the 8250 serial console path in the kernel config
so this direct QEMU boot test can report reliably. The QEMU run uses TCG with
`-cpu max`, an uncompressed initramfs, and `rdinit=/init` to avoid CI-specific
CPU-model and initramfs decompression failures.

The default is enabled for manual runs.

### `publish_release`

When enabled, the workflow creates or updates a GitHub Release and uploads the
generated `.deb` packages plus `BUILD-MANIFEST.txt`.

The default is disabled, so normal manual runs only upload workflow artifacts.

### `release_tag`

Optional release tag to create or update when `publish_release` is enabled.

If left blank, the workflow generates a tag like:

```text
cachyos-debian-stable-7.1.3-2-x64v2
```

If the workflow is manually run from an existing tag ref, that tag is used unless
`release_tag` is set.

### `mark_latest`

Controls whether the created or updated GitHub Release is marked as the latest
release. The default is enabled.

## Server-Oriented Kernel Configuration

The workflow runs the matching upstream `PKGBUILD` preparation logic instead of
maintaining a separate copy of its profile rules. It then ensures common Debian
server requirements, including:

- initramfs booting
- loadable kernel modules
- EFI systems
- dynamic preemption and high-resolution timers
- schedutil CPU frequency governor
- common cgroups, BPF, and pressure-stall interfaces
- Intel, AMD, Nouveau, and VirtIO graphics modules
- common USB, HID, audio, webcam, Bluetooth, and Wi-Fi modules
- common filesystems such as ext4, Btrfs, XFS, F2FS, exFAT, NTFS3, NFS, CIFS,
  OverlayFS, and SquashFS
- KVM, VirtIO, and VFIO modules
- WireGuard and common networking features

The build uses explicit x86-64-v1/v2/v3 targets. This repository is intended
for Debian 13/KVM server testing; select v1 or v2 on the current E5-2696 v2
guest, while v3 packages require a newer host with AVX2/BMI/FMA support.

## Validation

The workflow performs package validation before uploading artifacts:

- verifies that `.deb` files were produced
- verifies that image and header packages exist
- inspects packages with `dpkg-deb`
- runs `lintian --fail-on error` with a narrow allowlist for expected
  kernel-header helper binaries
- checks for a packaged `vmlinuz-*`
- checks for packaged kernel modules
- checks for installed header files
- optionally performs a minimal QEMU boot smoke test

## Release Assets

CNB builds do both of the following when successful:

1. Upload packages to a GitHub Release when `publish_release` is enabled.
2. Always mirror the same `.deb` files and `BUILD-MANIFEST.txt` into the GitHub
   Actions run Artifacts section (14-day retention).

Internally CNB first creates a temporary draft release named
`cnb-run-<github_run_id>` so the Actions job can download the packages. That
draft is deleted after Artifacts are uploaded and is not meant for end users.

To publish packages to a normal GitHub Release, keep `publish_release` enabled
(the CNB form default). You can either provide a `release_tag` or leave it blank
and let the workflow generate one from the kernel track, version, and CPU level.

The release publisher uses the workflow `GITHUB_TOKEN`, so the repository must
allow GitHub Actions to write repository contents. This workflow already declares
`contents: write`.

## Installing Packages

Download the generated `.deb` files from the matching GitHub Release or from the
workflow run Artifacts, then install the image and headers on a Debian-based
system:

```bash
sudo apt install ./linux-image-*.deb ./linux-headers-*.deb
sudo update-grub
sudo reboot
```

After rebooting, confirm the running kernel:

```bash
uname -a
```

Keep a known-good distribution kernel installed so you can select it from the
bootloader if the custom kernel does not work on your hardware.

## Important Notes

- This project repackages CachyOS kernel sources for Debian-based systems; it is
  not an official CachyOS project.
- CachyOS kernel sources and packaging metadata come from upstream CachyOS
  repositories at build time.
- Kernel compatibility depends on your hardware, firmware, bootloader, Secure
  Boot configuration, DKMS modules, and distribution release.
- Secure Boot users may need to sign the generated kernel or disable Secure Boot,
  depending on local policy.
- Proprietary or out-of-tree modules, such as NVIDIA DKMS modules, are not built
  by this workflow.

## Repository Layout

```text
.cnb.yml
.cnb/Dockerfile
.cnb/build-kernel.sh
.github/workflows/build-cachyos-kernel-cnb.yml
.github/workflows/build-cachyos-kernel-cnb-aggressive-v2.yml
README.md
```

The CNB path mirrors the controlling GitHub commit before dispatch so CNB
executes the same checked-in configuration.

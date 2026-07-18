<div style="border: 3px solid #6effaf; border-radius: 5px; overflow: hidden; display: inline-block;">
  <img src="assets/cachydebian.png" alt="image" style="display: block;">
</div>

# CachyOS Kernel Debian Builder

中文文档：[README.zh-CN.md](README.zh-CN.md) | English

This repository builds CachyOS Linux as installable Debian packages for
64-bit Debian server workloads. It produces both the latest stable server
kernel and the latest CachyOS release-candidate kernel for x86-64-v1, v2, and
v3 CPU baselines.

The target is a headless Debian/KVM server. The packages include initramfs,
VirtIO, serial console, networking, storage, KVM, WireGuard, and common
filesystems; a VirtIO-GPU device is not required.

## What It Builds

The workflow fetches the newest kernel metadata from the official
[CachyOS/linux-cachyos](https://github.com/CachyOS/linux-cachyos) packaging
repository, downloads the matching CachyOS kernel source tarball, applies a
server-oriented configuration pass, compiles the kernel, and packages the
result with the kernel's upstream Debian packaging target.

Each run builds six packages:

- Stable `linux-cachyos-server` with x86-64-v1/v2/v3.
- Latest `linux-cachyos-rc` with the CachyOS scheduler and x86-64-v1/v2/v3.

The kernel localversion and package/release names contain `x64v1`, `x64v2`, or
`x64v3`, so the required CPU baseline is visible in `uname -r`, package names,
Release names, artifacts, and `BUILD-MANIFEST.txt`.

Expected output includes standard `.deb` packages such as:

- `linux-image-*.deb`
- `linux-headers-*.deb`
- related generated kernel packages produced by `make bindeb-pkg`
- `BUILD-MANIFEST.txt` with source/version details and SHA256 checksums

## Workflow Trigger

The workflow supports both manual and scheduled runs. A scheduled run checks
both upstream `PKGBUILD` files once per day at 06:00 Beijing time and starts the
six-build matrix only when a new upstream `pkgver/pkgrel` has not already been
published by this repository. Scheduled builds publish versioned Releases
automatically.

Manual runs are started from the GitHub Actions tab with the `workflow_dispatch`
trigger and run the same six-build matrix.

## Manual Usage

1. Open the repository on GitHub.
2. Go to **Actions**.
3. Select **Build CachyOS Kernel Debian Packages**.
4. Click **Run workflow**.
5. Choose the desired inputs:
   - `runner`: GitHub-hosted or Blacksmith runner size.
   - `run_qemu_smoke_test`: whether to boot-test the built kernel in QEMU.
   - `publish_release`: whether to upload the final packages to a GitHub
     Release.
   - `release_tag`: optional tag to create/update when publishing a Release.
   - `mark_latest`: whether the Release should be marked as the latest.
6. Wait for the build to finish.
7. Download the generated artifacts from the workflow run.

Kernel builds are large and slow. A full run can take several hours and uses a
significant amount of GitHub-hosted runner disk space.

## Available Build Inputs

### `runner`

Supported values:

- `blacksmith-8vcpu-ubuntu-2404`
- `blacksmith-16vcpu-ubuntu-2404`
- `blacksmith-32vcpu-ubuntu-2404`
- `ubuntu-24.04`

The default is `blacksmith-16vcpu-ubuntu-2404`, which is a good fit for kernel
compilation because it provides substantially more CPU, memory, and disk space
than the default GitHub-hosted Ubuntu runner.

Blacksmith runners require the Blacksmith GitHub integration to be installed and
enabled for the repository's organization. If Blacksmith is not configured, use
the `ubuntu-24.04` fallback runner.

### Build Matrix

Every run builds these CPU baselines:

- `x64v1` / `generic`: broadest compatibility.
- `x64v2` / `generic_v2`: recommended for the current E5-2696 v2 VM.
- `x64v3` / `generic_v3`: requires AVX2, BMI1/2, FMA, and related features.

The workflow deliberately does not use `native`: a GitHub-hosted build would
optimize for the runner CPU, not the server where the kernel will run.

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

The workflow starts from the matching CachyOS configuration and applies separate
profiles:

- Stable: EEVDF, 300 Hz, idle tickless, lazy preemption, and THP madvise.
- Aggressive RC: CachyOS scheduler, 1000 Hz, full tickless, full preemption,
  and THP always.

Both profiles ensure common Debian server requirements, including:

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

Artifacts are always uploaded to the workflow run.

To publish the generated `.deb` packages to GitHub Releases, run the workflow
manually with `publish_release` enabled. You can either provide a `release_tag`
or leave it blank and let the workflow generate one from the kernel variant,
kernel version, and workflow run number.

The release publisher uses the workflow `GITHUB_TOKEN`, so the repository must
allow GitHub Actions to write repository contents. This workflow already declares
`contents: write`.

## Installing Packages

Download the generated `.deb` files from the workflow artifacts, then install the
image and headers on a Debian-based system:

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
.github/workflows/build-cachyos-kernel.yml
README.md
```

The workflow is self-contained and fetches the CachyOS kernel sources during the
GitHub Actions run.

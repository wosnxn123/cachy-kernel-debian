#!/usr/bin/env bash
# shellcheck disable=SC2154
set -Eeuo pipefail

required_env=(
  KERNEL_VARIANT REQUESTED_CPU_SCHEDULER CPU_TARGET CPU_LEVEL
  BUILD_PROFILE BUILD_TRACK RUN_QEMU_SMOKE_TEST PUBLISH_RELEASE
  GITHUB_REPOSITORY GITHUB_SHA GITHUB_RUN_NUMBER
)
for name in "${required_env[@]}"; do
  if [ -z "${!name:-}" ]; then
    echo "Required environment variable is missing: ${name}" >&2
    exit 1
  fi
done

# Default to skipping huge linux-image-*-dbg packages unless explicitly disabled.
SKIP_DEBUG_PACKAGES="${SKIP_DEBUG_PACKAGES:-true}"
case "${SKIP_DEBUG_PACKAGES}" in
  true|false) ;;
  *) echo "Unsupported SKIP_DEBUG_PACKAGES value: ${SKIP_DEBUG_PACKAGES}" >&2; exit 1 ;;
esac

case "${CPU_TARGET}:${CPU_LEVEL}" in
  generic:1|generic_v2:2|generic_v3:3) ;;
  *) echo "CPU target and level do not match: ${CPU_TARGET}:${CPU_LEVEL}" >&2; exit 1 ;;
esac

workspace="${CNB_BUILD_WORKSPACE:-$(pwd)}"
cd "${workspace}"
rm -rf artifacts build package-check qemu-test
mkdir -p artifacts build

echo "Building ${KERNEL_VARIANT} for x86-64-v${CPU_LEVEL} on $(nproc) CPUs"
git clone --depth=1 https://github.com/CachyOS/linux-cachyos.git build/linux-cachyos-packaging
packaging_commit="$(git -C build/linux-cachyos-packaging rev-parse HEAD)"

cd "build/linux-cachyos-packaging/${KERNEL_VARIANT}"
if [ "${REQUESTED_CPU_SCHEDULER}" != "upstream-default" ]; then
  export _cpusched="${REQUESTED_CPU_SCHEDULER}"
fi
export _processor_opt="${CPU_TARGET}"
# Keep every upstream PKGBUILD feature default.  This builder is intentionally
# not a copy of a long-lived CachyOS .config or patch list.
unset _build_zfs _build_nvidia_open _build_r8125 _build_debug _localmodcfg

# shellcheck disable=SC1091
source PKGBUILD
packaging_config_sha256="$(sha256sum config | awk '{print $1}')"

# These Arch-only companion packages need their own Debian packaging path.  Do
# not silently turn one off if CachyOS enables it upstream in the future.
for companion_option in _build_zfs _build_nvidia_open _build_r8125; do
  if [ "${!companion_option:-no}" = "yes" ]; then
    echo "Upstream enabled ${companion_option}; add its Debian package adapter before building." >&2
    exit 1
  fi
done

for setting in \
  _cpusched _cachy_config _HZ_ticks _tickrate _preempt _hugepage \
  _use_llvm_lto _cc_harder _per_gov _tcp_bbr3 _use_kcfi; do
  test -n "${!setting:-}"
done

CPU_SCHEDULER="${_cpusched}"
CACHY_CONFIG="${_cachy_config}"
HZ_TICKS="${_HZ_ticks}"
TICK_RATE="${_tickrate}"
PREEMPT_MODE="${_preempt}"
HUGEPAGE_MODE="${_hugepage}"
USE_LLVM_LTO="${_use_llvm_lto}"
CC_HARDER="${_cc_harder}"
PERFORMANCE_GOVERNOR="${_per_gov}"
TCP_BBR3="${_tcp_bbr3}"
USE_KCFI="${_use_kcfi}"

source_url=""
for source_item in "${source[@]}"; do
  candidate_url="${source_item#*::}"
  case "${candidate_url}" in
    https://github.com/CachyOS/linux/releases/download/*.tar.gz|\
    https://github.com/CachyOS/linux/releases/download/*.tar.xz|\
    https://github.com/CachyOS/linux/releases/download/*.tar.zst)
      source_url="${candidate_url}"
      break
      ;;
  esac
done
test -n "${source_url}"

cd "${workspace}/build"
source_archive="${source_url##*/}"
curl --fail --location --retry 5 --retry-delay 10 \
  --output "${source_archive}" "${source_url}"
tar -xf "${source_archive}"
ln -s "${workspace}/build/linux-cachyos-packaging/${KERNEL_VARIANT}/config" config

downloaded_patch_count=0
for source_item in "${source[@]}"; do
  patch_url="${source_item#*::}"
  if [[ "${patch_url}" != http* || "${patch_url}" != *.patch ]]; then
    continue
  fi
  curl --fail --location --retry 5 --retry-delay 10 \
    --output "${patch_url##*/}" "${patch_url}"
  downloaded_patch_count=$((downloaded_patch_count + 1))
done

export srcdir="${workspace}/build"
export startdir="${workspace}/build/linux-cachyos-packaging/${KERNEL_VARIANT}"
original_ci="${CI:-}"
original_github_run_id="${GITHUB_RUN_ID:-}"
export CI=""
export GITHUB_RUN_ID=""
set +o pipefail
prepare
set -o pipefail
export CI="${original_ci}"
export GITHUB_RUN_ID="${original_github_run_id}"

rm -f \
  "${_srcname}/localversion.10-pkgrel" \
  "${_srcname}/localversion.20-pkgname" \
  "${_srcname}/version"

source_dir="${workspace}/build/${_srcname}"
cd "${source_dir}"
upstream_prelocal_config_sha256="$(sha256sum .config | awk '{print $1}')"

cfg() {
  scripts/config "$@" || true
}

cfg --set-str LOCALVERSION "-x64v${CPU_LEVEL}-cachyos-${BUILD_PROFILE}"
case "${CPU_TARGET}" in
  generic) cfg --set-val X86_64_VERSION 1 ;;
  generic_v2) cfg --set-val X86_64_VERSION 2 ;;
  generic_v3) cfg --set-val X86_64_VERSION 3 ;;
esac

# Preserve the resolved CachyOS configuration and patch queue verbatim.  The
# two deliberate local deltas are the package namespace/CPU baseline above,
# plus disabling debug information when the caller requests no debug package.
if [ "${SKIP_DEBUG_PACKAGES}" = "true" ]; then
  cfg -d DEBUG_INFO
  cfg -d DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
  cfg -d DEBUG_INFO_DWARF4
  cfg -d DEBUG_INFO_DWARF5
  cfg -d DEBUG_INFO_BTF
  cfg -e DEBUG_INFO_NONE
else
  cfg -d DEBUG_INFO_NONE
  cfg -e DEBUG_INFO
  cfg -e DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
  cfg -d DEBUG_INFO_REDUCED
fi

build_flags=()
case "${USE_LLVM_LTO}" in
  none) ;;
  thin|thin-dist|full) build_flags=(CC=clang LD=ld.lld LLVM=1 LLVM_IAS=1) ;;
  *) echo "Unsupported upstream LTO mode: ${USE_LLVM_LTO}" >&2; exit 1 ;;
esac

make "${build_flags[@]}" olddefconfig
for required_config in \
  CONFIG_X86_64_VERSION="${CPU_LEVEL}" \
  "CONFIG_LOCALVERSION=\"-x64v${CPU_LEVEL}-cachyos-${BUILD_PROFILE}\""; do
  grep -qx "${required_config}" .config
done
resolved_config_sha256="$(sha256sum .config | awk '{print $1}')"

export KBUILD_BUILD_USER="cnb-cloud-build"
export KBUILD_BUILD_HOST="cnb.cool"
export KDEB_PKGVERSION="${pkgver}-${GITHUB_RUN_NUMBER}"
export KDEB_COMPRESS=xz
echo "Building Debian packages with $(nproc) jobs"
fakeroot make "${build_flags[@]}" -j"$(nproc)" bindeb-pkg
echo "Package build finished; collecting .deb files"

for deb in ../*.deb; do
  case "${deb}" in
    *-dbg_*.deb|*-dbg-*.deb)
      if [ "${SKIP_DEBUG_PACKAGES}" = "true" ]; then
        echo "Skipping debug-symbol package: ${deb}"
        rm -f "${deb}"
      else
        echo "Keeping debug-symbol package: ${deb}"
        mv "${deb}" "${workspace}/artifacts/"
      fi
      ;;
    *)
      echo "Keeping package: ${deb}"
      mv "${deb}" "${workspace}/artifacts/"
      ;;
  esac
done
cd "${workspace}"
shopt -s nullglob
debs=(artifacts/*.deb)
mapfile -t image_debs < <(find artifacts -maxdepth 1 -type f -name 'linux-image-*.deb' ! -name '*-dbg_*' ! -name '*-dbg-*.deb' | sort -V)
header_debs=(artifacts/linux-headers-*.deb)
test "${#debs[@]}" -gt 0
test "${#image_debs[@]}" -gt 0
test "${#header_debs[@]}" -gt 0
echo "Collected packages: ${#debs[@]}"

heartbeat() {
  local label="$1"
  local seconds=0
  while sleep 30; do
    seconds=$((seconds + 30))
    echo "Still working: ${label} (${seconds}s)"
  done
}

for deb in "${debs[@]}"; do
  echo "Validating package: ${deb}"
  dpkg-deb --info "${deb}"
  case "${deb}" in
    *-dbg_*.deb|*-dbg-*.deb)
      echo "Skipping contents/lintian for large debug-symbol package: ${deb}"
      continue
      ;;
  esac
  echo "Listing package contents: ${deb}"
  heartbeat "dpkg-deb --contents ${deb}" &
  heartbeat_pid=$!
  set +e
  dpkg-deb --contents "${deb}" > "${deb}.contents.txt"
  contents_status=$?
  set -e
  kill "${heartbeat_pid}" 2>/dev/null || true
  wait "${heartbeat_pid}" 2>/dev/null || true
  test "${contents_status}" -eq 0
  echo "Running lintian: ${deb}"
  heartbeat "lintian ${deb}" &
  heartbeat_pid=$!
  set +e
  timeout 8m lintian --fail-on error --suppress-tags unstripped-binary-or-object "${deb}"
  lintian_status=$?
  set -e
  kill "${heartbeat_pid}" 2>/dev/null || true
  wait "${heartbeat_pid}" 2>/dev/null || true
  if [ "${lintian_status}" -eq 124 ]; then
    echo "lintian timed out after 8 minutes for ${deb}" >&2
    exit 1
  fi
  test "${lintian_status}" -eq 0
  echo "Package validation finished: ${deb}"
done

echo "Extracting image package for content checks"
mkdir package-check
heartbeat "extract image package" &
heartbeat_pid=$!
dpkg-deb -x "${image_debs[0]}" package-check/image
kill "${heartbeat_pid}" 2>/dev/null || true
wait "${heartbeat_pid}" 2>/dev/null || true
echo "Extracting headers package for content checks"
heartbeat "extract headers package" &
heartbeat_pid=$!
dpkg-deb -x "${header_debs[0]}" package-check/headers
kill "${heartbeat_pid}" 2>/dev/null || true
wait "${heartbeat_pid}" 2>/dev/null || true
test -n "$(find package-check/image/boot -maxdepth 1 -type f -name 'vmlinuz-*' -print -quit)"
test -n "$(find package-check/image/lib/modules -mindepth 1 -maxdepth 1 -type d -print -quit)"
test -n "$(find package-check/image/lib/modules -type f \( -name '*.ko' -o -name '*.ko.xz' -o -name '*.ko.zst' -o -name modules.builtin \) -print -quit)"
test -n "$(find package-check/headers/usr/src -mindepth 1 -maxdepth 2 -type f -name Makefile -print -quit)"
echo "Package content checks passed"

if [ "${RUN_QEMU_SMOKE_TEST}" = "true" ]; then
  echo "Preparing QEMU smoke test"
  rm -rf qemu-test
  mkdir -p qemu-test/root qemu-test/initramfs/{bin,dev,proc,sys}
  dpkg-deb -x "${image_debs[0]}" qemu-test/root
  kernel_image="$(find qemu-test/root/boot -maxdepth 1 -type f -name 'vmlinuz-*' | sort -V | tail -n1)"
  echo "QEMU kernel image: ${kernel_image}"
  cp /bin/busybox qemu-test/initramfs/bin/busybox
  for applet in sh mount poweroff sleep; do
    ln -s busybox "qemu-test/initramfs/bin/${applet}"
  done
  mknod -m 600 qemu-test/initramfs/dev/console c 5 1
  mknod -m 666 qemu-test/initramfs/dev/null c 1 3
  cat > qemu-test/initramfs/init <<'EOF'
#!/bin/sh
mount -t proc proc /proc || true
mount -t sysfs sysfs /sys || true
mount -t devtmpfs devtmpfs /dev || true
[ -c /dev/console ] && exec >/dev/console 2>&1
echo CACHYOS_QEMU_BOOT_OK
sleep 2
poweroff -f || echo o > /proc/sysrq-trigger
EOF
  chmod +x qemu-test/initramfs/init
  (cd qemu-test/initramfs && find . -print0 | cpio --null -ov --format=newc) > qemu-test/initramfs.cpio

  echo "Starting QEMU smoke test (max 180s)"
  set +e
  qemu-system-x86_64 \
    -machine pc,accel=tcg -cpu max -m 2048M -smp 2 \
    -kernel "${kernel_image}" -initrd qemu-test/initramfs.cpio \
    -append "rdinit=/init init=/init console=ttyS0,115200 earlycon=uart,io,0x3f8,115200n8 earlyprintk=serial,ttyS0,115200 edd=off panic=30 oops=panic" \
    -display none -no-reboot -monitor none -serial file:qemu-test/serial.log &
  qemu_pid=$!
  boot_ok=0
  for second in $(seq 1 180); do
    if grep -q CACHYOS_QEMU_BOOT_OK qemu-test/serial.log 2>/dev/null; then
      boot_ok=1
      break
    fi
    kill -0 "${qemu_pid}" 2>/dev/null || break
    if [ $((second % 30)) -eq 0 ]; then
      echo "Waiting for QEMU boot marker (${second}s/180s)"
    fi
    sleep 1
  done
  if [ "${boot_ok}" -eq 1 ] && kill -0 "${qemu_pid}" 2>/dev/null; then
    kill "${qemu_pid}" 2>/dev/null || true
  fi
  wait "${qemu_pid}"
  qemu_status=$?
  set -e
  cat qemu-test/serial.log
  test "${boot_ok}" -eq 1
  echo "QEMU smoke test passed"
  if [ "${qemu_status}" -ne 0 ] && [ "${qemu_status}" -ne 143 ]; then
    echo "QEMU exited with status ${qemu_status} after the success marker."
  fi
fi

{
  echo "CachyOS source: ${source_url}"
  echo "CachyOS packaging repository: https://github.com/CachyOS/linux-cachyos"
  echo "CachyOS packaging commit: ${packaging_commit}"
  echo "CachyOS packaging config SHA256: ${packaging_config_sha256}"
  echo "CachyOS downloaded patch count: ${downloaded_patch_count}"
  echo "CachyOS prepared config SHA256 (before local deltas): ${upstream_prelocal_config_sha256}"
  echo "Resolved config SHA256: ${resolved_config_sha256}"
  echo "Source name: ${_srcname}"
  echo "Version: ${pkgver}-${pkgrel}"
  echo "Variant: ${KERNEL_VARIANT}"
  echo "Source track: ${BUILD_TRACK}"
  echo "Profile: ${BUILD_PROFILE}"
  echo "Configuration flow: live CachyOS config -> live CachyOS prepare() patch queue -> olddefconfig"
  echo "Local config deltas: LOCALVERSION, x86-64 CPU baseline, and DEBUG_INFO only when skip_debug_packages=true"
  echo "Skip debug packages: ${SKIP_DEBUG_PACKAGES}"
  echo "Scheduler: ${CPU_SCHEDULER}"
  echo "CachyOS config: ${CACHY_CONFIG}"
  echo "Timer frequency: ${HZ_TICKS} Hz"
  echo "Tick mode: ${TICK_RATE}"
  echo "Preemption: ${PREEMPT_MODE}"
  echo "Transparent hugepages: ${HUGEPAGE_MODE}"
  echo "LLVM LTO: ${USE_LLVM_LTO}"
  echo "O3 requested upstream: ${CC_HARDER}"
  echo "Performance governor requested upstream: ${PERFORMANCE_GOVERNOR}"
  echo "BBR3 requested upstream: ${TCP_BBR3}"
  echo "KCFI requested upstream: ${USE_KCFI}"
  echo "CPU target: ${CPU_TARGET}"
  echo "CPU baseline: x86-64-v${CPU_LEVEL}"
  echo "Kernel localversion: -x64v${CPU_LEVEL}-cachyos-${BUILD_PROFILE}"
  echo "Build provider: CNB Cloud Native Build ($(nproc) vCPU)"
  echo "GitHub Actions run: ${GITHUB_RUN_ID:-unknown}"
  echo "Built at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  sha256sum artifacts/*.deb
} > artifacts/BUILD-MANIFEST.txt

# Temporary draft release used only so GitHub Actions can pull packages as
# workflow Artifacts. The Actions job deletes this tag after upload.
if [ -n "${GITHUB_RUN_ID:-}" ] && [ -n "${GH_TOKEN:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ]; then
  artifact_tag="cnb-run-${GITHUB_RUN_ID}"
  artifact_title="CNB temporary artifacts for GitHub run ${GITHUB_RUN_ID}"
  artifact_notes="$(cat <<EOF
Temporary draft release for GitHub Actions Artifacts transfer.

GitHub Actions run: ${GITHUB_RUN_ID}
Track: ${BUILD_TRACK}
Variant: ${KERNEL_VARIANT}
CPU: x86-64-v${CPU_LEVEL}
This draft is deleted after the workflow uploads Artifacts.
EOF
)"
  if gh release view "${artifact_tag}" --repo "${GITHUB_REPOSITORY}" >/dev/null 2>&1; then
    gh release upload "${artifact_tag}" artifacts/*.deb artifacts/BUILD-MANIFEST.txt \
      --repo "${GITHUB_REPOSITORY}" --clobber
  else
    gh release create "${artifact_tag}" artifacts/*.deb artifacts/BUILD-MANIFEST.txt \
      --repo "${GITHUB_REPOSITORY}" \
      --target "${GITHUB_SHA}" \
      --draft \
      --title "${artifact_title}" \
      --notes "${artifact_notes}" \
      --latest=false
  fi
  echo "Temporary artifact handoff release: ${artifact_tag}"
  echo "##[set-output artifact_tag=${artifact_tag}]"
fi

if [ "${PUBLISH_RELEASE}" = "true" ]; then
  test -n "${GH_TOKEN:-}"
  if [ -n "${RELEASE_TAG:-}" ]; then
    release_tag="${RELEASE_TAG}"
  elif [ "${BUILD_TRACK}" = "custom" ]; then
    release_variant="${KERNEL_VARIANT#linux-cachyos-}"
    release_tag="cachyos-debian-custom-${release_variant}-${CPU_SCHEDULER}-${pkgver}-${pkgrel}-x64v${CPU_LEVEL}"
  else
    release_tag="cachyos-debian-${BUILD_TRACK}-${pkgver}-${pkgrel}-x64v${CPU_LEVEL}"
  fi
  release_name="CachyOS Debian Kernel ${BUILD_TRACK}, ${KERNEL_VARIANT}, ${CPU_SCHEDULER}, x86-64-v${CPU_LEVEL}"
  release_flags=(--repo "${GITHUB_REPOSITORY}" --title "${release_name}" --notes-file artifacts/BUILD-MANIFEST.txt)
  if [ "${BUILD_TRACK}" = "aggressive" ]; then
    release_flags+=(--prerelease)
  fi
  if [ "${MARK_LATEST:-false}" = "true" ]; then
    release_flags+=(--latest)
  fi

  if gh release view "${release_tag}" --repo "${GITHUB_REPOSITORY}" >/dev/null 2>&1; then
    gh release edit "${release_tag}" "${release_flags[@]}"
    gh release upload "${release_tag}" artifacts/*.deb artifacts/BUILD-MANIFEST.txt \
      --repo "${GITHUB_REPOSITORY}" --clobber
  else
    if [ "${MARK_LATEST:-false}" != "true" ]; then
      release_flags+=(--latest=false)
    fi
    gh release create "${release_tag}" artifacts/*.deb artifacts/BUILD-MANIFEST.txt \
      --target "${GITHUB_SHA}" "${release_flags[@]}"
  fi
  echo "GitHub Release: https://github.com/${GITHUB_REPOSITORY}/releases/tag/${release_tag}"
  echo "##[set-output release_tag=${release_tag}]"
fi

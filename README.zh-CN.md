# CachyOS Debian 内核构建器

[English README](README.md) | 中文文档

本仓库为 Debian 13 和 KVM 无桌面服务器构建 CachyOS 内核 `.deb` 包。它不是 CachyOS 官方 Debian 仓库，而是使用 GitHub Actions 重新打包上游 CachyOS 内核。

## 构建内容

每次构建包含两条内核线和三个 CPU 基线，共六个构建：

- 稳定服务器版：`linux-cachyos-server` + EEVDF。
- 最新激进测试版：`linux-cachyos-rc` + CachyOS 调度器。
- 每条内核线均构建 `x64v1`、`x64v2`、`x64v3`。

内核版本、`uname -r`、`.deb` 包名、Release 名称、Workflow Artifact 名称和 `BUILD-MANIFEST.txt` 都会标明 `x64v1`、`x64v2` 或 `x64v3`。

## CPU 基线

| 标识 | 配置 | 说明 |
| --- | --- | --- |
| `x64v1` | `generic` | 兼容性最广 |
| `x64v2` | `generic_v2` | 需要 x86-64-v2 指令集：SSSE3、SSE4.1、SSE4.2、POPCNT、CX16、LAHF/SAHF |
| `x64v3` | `generic_v3` | 需要 x86-64-v3 指令集：AVX2、BMI1/2、FMA、MOVBE、F16C 等 |

`x64v2` 和 `x64v3` 不是 CPU 型号，而是最低指令集等级。安装前应在目标机器执行 `lscpu` 检查 CPU flags；缺少对应指令集的机器不能启动该等级的内核。

例如：

```bash
lscpu | grep -E 'Flags|avx2|bmi1|bmi2|fma|sse4_1|sse4_2|popcnt'
```

工作流不会使用 `native`。GitHub runner 上的 `native` 会针对 runner CPU 编译，而不是针对你的服务器 CPU。需要 Ivy Bridge 原生优化时，必须在目标 VM 或同型号 CPU 的机器上本地编译。

## 自动构建

工作流每天北京时间 06:00（UTC 22:00）检查 CachyOS 上游的两个 `PKGBUILD`。只有发现新的 `pkgver/pkgrel` 尚未发布时，才会启动六个构建，避免重复消耗 runner 时间。

自动构建会：

- 生成每个 CPU 基线独立的 Release；
- 上传带 `x64vN` 标识的 `.deb` 和 `BUILD-MANIFEST.txt`；
- 使用 QEMU 做最小启动测试；
- 稳定版使用 300 Hz、idle tickless、lazy preemption、THP madvise；
- 激进 RC 使用 1000 Hz、full tickless、full preemption、THP always。

稳定版和激进 RC 的配置不同是有意的：稳定版优先可预测性和长期运行，RC 版优先测试最新内核和更激进的调度参数。因此两者不是只更换内核源码的公平性能对比；要做严格对比，应使用相同 profile。

## 手动构建

进入 GitHub 的 **Actions**，选择 **Build CachyOS Kernel Debian Packages**，Branch 选择 `main`，然后运行。手动运行也会构建完整的六项矩阵。

推荐 runner：`ubuntu-24.04`。Blacksmith runner 只有在你的 GitHub 组织已启用对应集成时才能使用。

构建成功后，在对应 Release 或 Workflow Artifact 下载普通的 image 和 headers 包，不要下载 `-dbg` 包：

```bash
apt install ./linux-image-*.deb ./linux-headers-*.deb
update-grub
reboot
```

请保留一个已知可用的 Debian 或 XanMod 内核作为 GRUB 回退项。安装前检查 `BUILD-MANIFEST.txt` 中的版本、CPU 基线和 SHA256。

## 适用范围

本仓库专门面向 Debian 服务器/KVM 客户机，不以桌面图形体验为目标。配置包含 initramfs、VirtIO、串口控制台、VirtIO 网络/磁盘、KVM、VFIO、WireGuard 和常见文件系统；不需要打开 VirtIO-GPU 设备。

## 相关链接

- [English README](README.md)
- [GitHub Actions workflow](.github/workflows/build-cachyos-kernel.yml)
- [CachyOS kernel packaging](https://github.com/CachyOS/linux-cachyos)
- [CachyOS kernel source releases](https://github.com/CachyOS/linux/releases)

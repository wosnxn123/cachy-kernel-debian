# CachyOS Debian 内核构建器

[English README](README.md) | 中文文档

本仓库为 Debian 13 和 KVM 无桌面服务器构建 CachyOS 内核 `.deb` 包。它不是 CachyOS 官方 Debian 仓库，而是使用 GitHub Actions 重新打包上游 CachyOS 内核。

## 构建内容

每次手动构建只生成一个组合。CNB 菜单提供 official default、server、RC、LTS、EEVDF、BORE、BMQ、hardened、RT-BORE 和 Deckify 变体，以及 `x64v1`、`x64v2`、`x64v3` CPU 基线和调度器选择。

所选源码变体执行对应 CachyOS 官方 `PKGBUILD` 的 `prepare()`，由上游直接决定补丁、调度器、CachyOS config、LTO/编译器、HZ、tick、preemption、THP、O3、governor、BBR3 和 KCFI。准备阶段采用上游正式构建 profile，而不是它仅供 CI 加速的体积优化回退，因此上游 `cc_harder=yes` 会保留 O3。随后固定叠加本仓库的 Debian/KVM 服务端兼容配置，并设置所选 `x64vN` CPU 基线与可见标识。Release 与 `BUILD-MANIFEST.txt` 会记录最终解析出的 profile。

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

## 构建触发

常规手动构建使用 **Build CachyOS Kernel on CNB**，每次只构建一个组合。GitHub/Blacksmith 备用入口为 **Build Custom CachyOS Kernel Debian Package**（同样每次只构建一个组合）；旧的一次构建六个的入口已取消。

**Check and build aggressive x64v2 on CNB** 是唯一的自动工作流：每十天检查一次上游 RC 版本，只有对应的 `aggressive / generic_v2` Release 不存在时才触发 CNB 编译。手动运行该工作流时可选择是否跳过 `-dbg`（默认跳过）。

## 手动构建

进入 GitHub 的 **Actions**，选择 **Build CachyOS Kernel on CNB**，Branch 选择 `main`，然后运行。可选择：

- `kernel_variant`：CachyOS 官方仓库当前提供的 default、server、RC、LTS、EEVDF、BORE、BMQ、hardened、RT-BORE 和 Deckify 变体；
- `cpu_target`：`generic`、`generic_v2` 或 `generic_v3`，产物分别标记为 `x64v1`、`x64v2`、`x64v3`；
- `cpu_scheduler`：使用所选变体的 `upstream-default`，或者手动覆盖为指定调度器；
- `release_tag`：可选 Release 标签；留空则自动生成；
- `skip_debug_packages`：是否跳过巨大的 `linux-image-*-dbg` 调试包，默认跳过。

当前这台无桌面 Ivy Bridge 级 KVM 客户机建议选择 `linux-cachyos-rc`、`generic_v2` 与 `upstream-default`。推荐使用 `upstream-default`，因为它会保留对应官方变体预期的 profile；手动混搭调度器属于高级测试用途。

## CNB 云原生构建

**Build CachyOS Kernel on CNB** 工作流以 GitHub Actions 负责调度和显示状态，把真正吃 CPU 的编译放到 CNB 云原生构建中。

执行过程如下：

1. GitHub 将本次运行的准确 Commit 推送到指定 CNB 仓库；
2. GitHub 通过 StartBuild API 触发 `api_trigger_kernel`；
3. CNB 使用 32 vCPU amd64 容器编译，并执行包校验及可选 QEMU 启动测试；
4. CNB 将 `.deb` 与 `BUILD-MANIFEST.txt` 上传到 GitHub Release（若启用 `publish_release`），并创建临时 draft `cnb-run-<run_id>` 供 Actions 拉取；
5. GitHub 轮询 CNB 成功后，下载临时 draft 并上传到本次工作流的 Artifacts，再删除临时 draft；
6. 任务摘要中会给出 CNB 实时日志链接。

CNB 每次只构建一个选择的组合，避免误触发并行内核编译并使 CNB 核时用量可控。

### 接入步骤

1. 在 CNB 创建空仓库。fork 默认使用 `<你的 GitHub 用户或组织>/cachy-kernel-debian`；也可使用任意 CNB `组织/仓库` 路径；
2. 创建可写代码仓库且包含 `repo-cnb-trigger:rw` 权限的 CNB 访问令牌；
3. 在 GitHub fork 中打开 **Settings -> Secrets and variables -> Actions**，在 Secrets 创建 `CNB_TOKEN`，将 CNB 令牌粘贴为值；
4. 若 CNB 路径与默认值不同，在同一页面的 Variables 创建 `CNB_REPO`，值为 `组织/仓库`；
5. 在 GitHub Actions 运行 **Build CachyOS Kernel on CNB**。

CNB 不会获得 GitHub 提交代码的权限。GitHub 使用 `CNB_TOKEN` 将工作流 Commit 同步至 CNB；CNB 只收到当前 GitHub 任务的临时令牌，用于创建 Release 和上传 `.deb`，其权限仅为 `contents: write`。调度任务结束或被取消时，这个令牌会失效，CNB 不保存永久 GitHub 凭据。CNB 路径会发布 GitHub Release（可选），并且成功后也会在对应 GitHub Actions 运行页生成 Workflow Artifacts。相关官方文档：[StartBuild API](https://api.cnb.cool/#/operations/StartBuild)、[CNB 构建节点](https://docs.cnb.cool/zh/build/build-node.html)。

### 每十天的激进 x64v2 检查

该自动工作流固定为 `linux-cachyos-rc`、`generic_v2`（`x64v2`）与 `upstream-default`，并使用固定的 Debian/KVM 服务端兼容配置。GitHub 每天只做轻量计时检查；未满十天不会拉取上游、更不会启动 CNB。满十天后才检查 RC 的 `pkgver/pkgrel`，将检查时间写入 `CNB_AGGRESSIVE_V2_LAST_CHECK` Actions Variable，并且仅在没有对应 Release 时启动构建。

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
- [CNB dispatcher workflow](.github/workflows/build-cachyos-kernel-cnb.yml)
- [Ten-day aggressive x64v2 workflow](.github/workflows/build-cachyos-kernel-cnb-aggressive-v2.yml)
- [CNB pipeline](.cnb.yml)
- [CachyOS kernel packaging](https://github.com/CachyOS/linux-cachyos)
- [CachyOS kernel source releases](https://github.com/CachyOS/linux/releases)

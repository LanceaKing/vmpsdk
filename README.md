# VMProtect SDK

[![Build examples](https://github.com/LanceaKing/vmpsdk/actions/workflows/build.yml/badge.svg)](https://github.com/LanceaKing/vmpsdk/actions/workflows/build.yml)

VMProtect SDK 的接口文件、库和示例，用于了解代码保护标记、授权验证和序列号生成。
内容提取自 `VMProtectSDK-3.5.0.1249.zip`，版本号沿用原包文件名。SDK、示例源码和工程文件保持原始内容。

## 仓库内容

| 目录 | 内容 |
| --- | --- |
| [Include](Include/) | C/C++、Pascal、ASM、VB6 的 SDK 接口声明 |
| [Lib](Lib/) | SDK 库文件 |
| [Code Markers](Examples/Code%20Markers/) | 在代码中标记保护区域的示例 |
| [Licensing](Examples/Licensing/) | 授权验证示例 |
| [KeyGen](Examples/KeyGen/) | 序列号生成库及调用示例 |
| [Scripts](Examples/Scripts/) | VMProtect 脚本示例及配套程序 |

## 获取源码

需要 Git、Python 3 和支持符号链接的文件系统。

```bash
git -c core.symlinks=true clone https://github.com/LanceaKing/vmpsdk.git
cd vmpsdk
python3 ci/verify.py
```

Windows 需要开启开发者模式或使用管理员权限，以便创建符号链接。
请使用 Git 克隆。GitHub 的源码 ZIP 不会创建这些链接。

## 下载编译好的示例

打开 [Build examples](https://github.com/LanceaKing/vmpsdk/actions/workflows/build.yml)。选择一次成功的构建，在 **Artifacts** 中下载对应项目的 ZIP。

文件名格式为 `<平台>-<架构>-<工具链>-<项目>.zip`，例如：

- `windows-x86-msvc-markers.zip`：Windows x86 的代码保护标记示例。
- `linux-x64-gcc-markers.zip`：Linux x64 的代码保护标记示例。
- `macos-x64-xcode-licensing.zip`：macOS x64 的授权验证示例。
- `windows-any-net-keygen-usage.zip`：.NET AnyCPU 的序列号生成调用示例。

每个 ZIP 包含一个项目的输出及所需 SDK 或 KeyGen 库。解压时保留全部文件和目录结构。
macOS 示例面向 Intel x64。本 SDK 不含 ARM64 库。

这些产物是未经 VMProtect 保护的示例。构建通过不代表保护或授权流程验证通过。
DDK 示例仅验证编译和打包，不加载驱动。

## 构建示例

本地构建命令、支持的工具链和验证范围见 [构建与验证](docs/building.md)。
构建在 `.build/work/` 中进行，输出位于 `.build/artifacts/`，打包后的 ZIP 位于 `.build/archives/`。

更多说明：

- [SDK 提取与校验](docs/sdk-extraction.md)
- [Windows 工具链](docs/windows-toolchains.md)
- [构建产物约定](docs/build-artifacts.md)

## 许可

原始 SDK 和示例的版权及许可归各自权利人所有。本仓库未为这些文件另行授予开源许可。

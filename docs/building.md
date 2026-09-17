# 构建与验证

本文说明 CI 的构建范围、缓存、验证边界和本地构建方法。
Windows 工具链的来源、安装细节和兼容处理见 [Windows 工具链](windows-toolchains.md)。

## 构建流程

[`build.yml`](../.github/workflows/build.yml) 在 push、pull request 或手动触发时运行。
所有构建使用 `.build/work/` 中的副本，构建输出放在 `.build/artifacts/`。每个项目分别打包到 `.build/archives/` 并上传至 Actions artifacts。
构建前后校验全部导入文件。构建副本也校验原始文件摘要。源文件、工程及 SDK 不打补丁、不重写、不自动升级。

## 产物与打包

下载文件统一命名为 `<平台>-<架构>-<工具链>-<项目>.zip`，例如 `windows-x86-masm-markers.zip`、`linux-x64-gcc-markers.zip`、`macos-x64-xcode-licensing.zip`。
平台和架构表示实际产物：MinGW 交叉编译使用 `windows-x86`，原始 .NET 工程使用 `windows-any`。
ZIP 根目录直接包含该项目的程序和运行依赖。macOS `.app` 和 `.dSYM` 保留自身目录结构。KeyGen 库与调用示例分别使用 `keygen`、`keygen-usage`，调用示例携带所需的库。
打包保留运行配置、manifest、映射文件、调试符号和导入库，排除构建中间文件。Unix 执行权限和符号链接保存在 ZIP 中。
[`package.py`](../ci/package.py) 定义每个项目的文件清单。上传使用 `archive: false`，下载后无需再解开一层压缩包。后续修改遵守 [`AGENTS.md`](../AGENTS.md)。

完整规则见 [构建产物约定](build-artifacts.md)。

## 依赖缓存

使用 [`actions/cache`](https://github.com/actions/cache) 缓存 Linux 编译器安装包、macOS FPC 下载文件、Windows MASM32 / VB6 / RAD Studio XE5 / WDK 7.1 工具链下载包、.NET 引用程序集和 Lazarus/FPC 安装目录。
缓存键包含 runner 平台、架构及依赖版本或安装脚本摘要。APT 还包含解析后的安装计划摘要。依赖变化会生成新缓存。
首次成功构建写入缓存，后续构建恢复缓存。Windows Lazarus/FPC 精确命中后跳过下载安装。示例程序每次重新编译，产物仍上传至 Artifacts。

## 构建矩阵

| Runner | 构建内容 | 构建方式 |
| --- | --- | --- |
| Ubuntu 24.04 | GCC Code Markers，Linux x86 / x64 | 直接运行原 `makeit.sh`，运行正确及错误密码的 smoke test |
| Ubuntu 24.04 | MinGW Code Markers，Windows x86 | 按原 `makeit.bat` 的 windres、c++ 参数交叉编译 |
| macOS 15 Intel | GCC Code Markers，x64 | 直接运行原 `makeit.sh`，运行密码 smoke test |
| macOS 15 Intel | Free Pascal Code Markers，x64 | 原 `makeit.sh` 参数，加当前 SDK、架构及库搜索路径，运行密码 smoke test |
| macOS 15 Intel | Code Markers / Licensing Xcode，x64 | 原 `.xcodeproj`，通过命令行指定当前 SDK、部署版本、关闭签名 |
| Windows 2022 | MSVC Code Markers / Licensing，x86 | 原 `.vcxproj`，命令行指定 v143 和 Windows SDK |
| Windows 2022 | MSVC Code Markers / Licensing，x64 | 原工程仅定义 Win32。直接编译同一组源文件和资源 |
| Windows 2022 | MASM Code Markers，x86 | MASM32 v9 自带的 ML 6.14 / LINK 5.12，沿用原 `makeit.bat` 的汇编和链接参数 |
| Windows 2022 | VB6 Code Markers / Licensing，x86 | VB6 6.00.8176，以 `/make` 编译原 `.vbp`，通过 `/outdir` 指定产物目录 |
| Windows 2022 | BCB Code Markers / Licensing，x86 | C++Builder XE5 Update 2，直接编译原 C++ / DFM，静态链接 VCL 和 RTL，生成 EXE 和详细 MAP |
| Windows 2022 | Delphi Code Markers / Licensing / KeyGen 调用示例，x86 | RAD Studio XE5 Update 2 的 `dcc32.exe` 直接编译原 `.dpr`，生成 EXE 和详细 MAP |
| Windows 2022 | Licensing DDK，x86 | WDK 7.1，直接运行原 `make.bat`、`MAKEFILE` 和 `SOURCES`，使用 XP free 构建环境 |
| Windows 2022 | KeyGen DLL 和调用示例，x86 / x64 | 按旧 `.vcproj` 的源文件、资源与 `.def` 构建。原工程无需转换 |
| Windows 2022 | .NET Code Markers / Licensing / KeyGen / Usage | 原 `.csproj`，NuGet reference assemblies 保留 v2.0 / v4.0 目标框架，命令行补齐引用路径 |
| Windows 2022 | Free Pascal Code Markers，x86 | FPC 3.2.2，沿用 `makeit.bat` 参数，独立 `fpc` job |
| Windows 2022 | Lazarus Code Markers，x86 | Lazarus 4.0 / FPC 3.2.2，使用原源文件及预编译 LCL units，独立 `lazarus` job |

## 验证范围与兼容处理

GUI 示例验证编译和链接。BCB 和 Delphi 还在原生 Windows runner 上检查各自两个主窗口的标题及正常关闭，不测试按钮或授权流程。KeyGen 调用示例使用原有空产品参数，因此运行输出错误码是示例的预期行为，不能视为实际签发验证。
这里构建的是未保护示例，不执行 VMProtect 加壳，也不证明授权服务或保护后的程序行为。

兼容参数也仅限 CI：MinGW 在外部 include 目录建立 `Resource.h` → 原 `resource.h` 的别名，以适配 Linux 大小写规则。KeyGen DLL 用 MSVC `/FIstring` 补充旧 STL 曾间接包含的标准头文件。

### 未纳入标准 runner 的项目

这些文件完整保留，未用跳过或 `continue-on-error` 冒充构建通过：

- Examples/Scripts：保留原预编译程序及 `.vmp` 配置。没有相应程序源码，无法重新编译。
- KeyGen/PHP：解释执行示例，无编译目标。

## 本地构建与验证

以下命令均在仓库根目录执行。工具链安装步骤见 [构建工作流](../.github/workflows/build.yml)。

### Linux

```bash
python3 ci/verify.py
python3 ci/prepare.py
# Linux：预先安装 g++-multilib、g++-mingw-w64-i686
bash ci/build-unix.sh linux
python3 ci/verify.py --root .build/work --build-tree
python3 ci/package.py linux-x64-gcc-markers
```

### macOS

macOS 使用 `gcc`、`fpc`、`xcode-markers` 或 `xcode-licensing` 参数。需要 Intel Mac。本包的 Mach-O SDK 只有 i386/x86_64，没有 ARM64。

### Windows

Windows 使用 `./ci/build-windows.ps1 -Kind msvc -Arch x86`，或 `masm` / `vb6` / `bcb` / `delphi` / `ddk` / `net` / `fpc` / `lazarus`。环境准备见 workflow。

MASM 只支持 x86：准备 7-Zip 后运行 `./ci/install-masm32.ps1`，再运行 `python ci/prepare.py` 和 `./ci/build-windows.ps1 -Kind masm -Arch x86`。

VB6 只支持 x86：在 Windows x64 / PowerShell 7.4+ 环境运行 `./ci/install-vb6.ps1`，再运行 `python ci/prepare.py` 和 `./ci/build-windows.ps1 -Kind vb6 -Arch x86`。安装 MSI 和注册组件需要管理员权限。GitHub Windows runner 已具备该权限。

BCB 和 Delphi 只支持 x86：在 Windows / PowerShell 7 环境准备 7-Zip，运行 `./ci/install-radstudio-xe5.ps1`，再运行 `python ci/prepare.py` 和 `./ci/build-windows.ps1 -Kind bcb -Arch x86` 或 `-Kind delphi -Arch x86`。

DDK 原工程只配置 x86：在 Windows / PowerShell 7 环境准备 7-Zip，以管理员权限运行 `./ci/install-wdk71.ps1`，再运行 `python ci/prepare.py` 和 `./ci/build-windows.ps1 -Kind ddk -Arch x86`。

Windows FPC 和 Lazarus 使用同一套 `C:\lazarus` 工具链安装和缓存，分别通过 `-Kind fpc -Arch x86` 和 `-Kind lazarus -Arch x86` 构建，各自上传 `windows-x86-fpc-markers.zip` 和 `windows-x86-lazarus-markers.zip`。

## 参考

[GitHub runner 标签](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)、[Windows 2022 工具清单](https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md)、[Free Pascal 下载](https://www.freepascal.org/download.html)。

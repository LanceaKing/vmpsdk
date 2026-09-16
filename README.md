# VMProtect SDK

[![Build examples](https://github.com/LanceaKing/vmpsdk/actions/workflows/build.yml/badge.svg)](https://github.com/LanceaKing/vmpsdk/actions/workflows/build.yml)

从 `VMProtectSDK-3.5.0.1249.zip` 提取的 SDK 与示例。版本号沿用输入文件名。

- 原始 ZIP SHA-256：`4b55d8c61ab7f3f5fb8bb75f32fb1eb35f8dd6441dcf0d9337357322e7f3beb9`。
- `Include/`、`Lib/` 以及保留的示例源码、工程、资源和 `makeit.*` 均保留原始字节。
- 移除 Examples 内的 21 个预编译程序（含示例驱动）和 1 个程序别名；保留 `Examples/Scripts/` 下全部 5 个 executable，以及 `.vmp`、`.map`、`.res`、应用资源与依赖库。
- 48 个重复 SDK 文件改为指向 `Include/` 或 `Lib/` 的相对符号链接；增加 2 个 GCC Linux SDK 链接，使原始 `makeit.sh` 能找到库。
- 替换链接前逐字节匹配原件。因此 BCB 目录中原有的 COFF import library 仍指向相同的 COFF 文件，不擅自换成 OMF。

原始 SDK 和示例的版权及许可归各自权利人所有；此仓库未为这些文件另行授予开源许可。

## 重放提取

需要 Python 3 以及支持符号链接的文件系统。将 `extract.py` 放入新目录：

```bash
mkdir vmpsdk-extracted
cp extract.py vmpsdk-extracted/
python3 vmpsdk-extracted/extract.py /path/to/VMProtectSDK-3.5.0.1249.zip
```

内容写入脚本所在目录，不依赖调用时的工作目录。若 `Examples/`、`Include/`、`Lib/` 或清单已存在，脚本拒绝覆盖。
脚本校验 ZIP CRC、拒绝越界路径，记录原包摘要、保留文件摘要、链接及删除原因到 [`extraction-manifest.json`](extraction-manifest.json)。

克隆时保留实际符号链接：

```bash
git -c core.symlinks=true clone https://github.com/LanceaKing/vmpsdk.git
cd vmpsdk
python3 ci/verify.py
```

Windows 需要允许创建符号链接（开发者模式或管理员权限）；GitHub Windows runner 在 checkout 前配置 `core.symlinks=true`。
仅下载 GitHub 源码 ZIP 不会替你创建这些链接。

## GitHub Actions 构建

[`build.yml`](.github/workflows/build.yml) 在 push、pull request 或手动触发时运行。
所有构建使用 `.build/work/` 中的副本，构建输出放在 `.build/artifacts/`。每个项目分别打包到 `.build/archives/` 并上传至 Actions artifacts。
构建前后校验全部导入文件；构建副本也校验原始文件摘要。源文件、工程及 SDK 不打补丁、不重写、不自动升级。

下载文件统一命名为 `<平台>-<架构>-<工具链>-<项目>.zip`，例如 `windows-x86-masm-markers.zip`、`linux-x64-gcc-markers.zip`、`macos-x64-xcode-licensing.zip`。
平台和架构表示实际产物：MinGW 交叉编译使用 `windows-x86`，原始 .NET 工程使用 `windows-any`。
ZIP 根目录直接包含该项目的程序和运行依赖；macOS `.app` 和 `.dSYM` 保留自身目录结构。KeyGen 库与调用示例分别使用 `keygen`、`keygen-usage`，调用示例携带所需的库。
打包保留运行配置、manifest、映射文件、调试符号和导入库，排除构建中间文件。Unix 执行权限和符号链接保存在 ZIP 中。
[`package.py`](ci/package.py) 定义每个项目的文件清单；上传使用 `archive: false`，下载后无需再解开一层压缩包。后续修改遵守 [`AGENTS.md`](AGENTS.md)。

使用 [`actions/cache`](https://github.com/actions/cache) 缓存 Linux 编译器安装包、macOS FPC 下载文件、Windows MASM32 / VB6 / RAD Studio XE5 / WDK 7.1 工具链下载包、.NET 引用程序集和 Lazarus/FPC 安装目录。
缓存键包含 runner 平台、架构及依赖版本或安装脚本摘要；APT 还包含解析后的安装计划摘要。依赖变化会生成新缓存。
首次成功构建写入缓存，后续构建恢复缓存；Windows Lazarus/FPC 精确命中后跳过下载安装。示例程序每次重新编译，产物仍上传至 Artifacts。

| Runner | 构建内容 | 构建方式 |
| --- | --- | --- |
| Ubuntu 24.04 | GCC Code Markers，Linux x86 / x64 | 直接运行原 `makeit.sh`，运行正确及错误密码的 smoke test |
| Ubuntu 24.04 | MinGW Code Markers，Windows x86 | 按原 `makeit.bat` 的 windres、c++ 参数交叉编译 |
| macOS 15 Intel | GCC Code Markers，x64 | 直接运行原 `makeit.sh`，运行密码 smoke test |
| macOS 15 Intel | Free Pascal Code Markers，x64 | 原 `makeit.sh` 参数，加当前 SDK、架构及库搜索路径，运行密码 smoke test |
| macOS 15 Intel | Code Markers / Licensing Xcode，x64 | 原 `.xcodeproj`，通过命令行指定当前 SDK、部署版本、关闭签名 |
| Windows 2022 | MSVC Code Markers / Licensing，x86 | 原 `.vcxproj`，命令行指定 v143 和 Windows SDK |
| Windows 2022 | MSVC Code Markers / Licensing，x64 | 原工程仅定义 Win32；直接编译同一组源文件和资源 |
| Windows 2022 | MASM Code Markers，x86 | MASM32 v9 自带的 ML 6.14 / LINK 5.12，沿用原 `makeit.bat` 的汇编和链接参数 |
| Windows 2022 | VB6 Code Markers / Licensing，x86 | VB6 6.00.8176，以 `/make` 编译原 `.vbp`，通过 `/outdir` 指定产物目录 |
| Windows 2022 | BCB Code Markers / Licensing，x86 | C++Builder XE5 Update 2，直接编译原 C++ / DFM，静态链接 VCL 和 RTL，生成 EXE 和详细 MAP |
| Windows 2022 | Delphi Code Markers / Licensing / KeyGen 调用示例，x86 | RAD Studio XE5 Update 2 的 `dcc32.exe` 直接编译原 `.dpr`，生成 EXE 和详细 MAP |
| Windows 2022 | Licensing DDK，x86 | WDK 7.1，直接运行原 `make.bat`、`MAKEFILE` 和 `SOURCES`，使用 XP free 构建环境 |
| Windows 2022 | KeyGen DLL 和调用示例，x86 / x64 | 按旧 `.vcproj` 的源文件、资源与 `.def` 构建；原工程无需转换 |
| Windows 2022 | .NET Code Markers / Licensing / KeyGen / Usage | 原 `.csproj`，NuGet reference assemblies 保留 v2.0 / v4.0 目标框架，命令行补齐引用路径 |
| Windows 2022 | Free Pascal / Lazarus Code Markers，x86 | Lazarus 4.0 / FPC 3.2.2；FPC 沿用 `makeit.bat` 参数；Lazarus 使用原源文件及预编译 LCL units |

GUI 示例验证编译和链接；BCB 和 Delphi 还在原生 Windows runner 上检查各自两个主窗口的标题及正常关闭，不测试按钮或授权流程。KeyGen 调用示例使用原有空产品参数，因此运行输出错误码是示例的预期行为，不能视为实际签发验证。
这里构建的是未保护示例，不执行 VMProtect 加壳，也不证明授权服务或保护后的程序行为。

兼容参数也仅限 CI：MinGW 在外部 include 目录建立 `Resource.h` → 原 `resource.h` 的别名，以适配 Linux 大小写规则；KeyGen DLL 用 MSVC `/FIstring` 补充旧 STL 曾间接包含的标准头文件。

MASM 使用 [CodingCrew 的 MASM32 v9 安装包](https://www.codingcrew.de/masm32/download/m32v9r.zip)，SHA-256 固定为 `000a660fce59e619ea608a889b9ae1e43ad1dfcb81ef79ca22a0d67503cd0205`。
[`install-masm32.ps1`](ci/install-masm32.ps1) 校验下载或缓存的安装包，用 runner 自带的 7-Zip 提取 `install.exe` 内嵌的数据，并编译 MASM32 静态库；不运行交互式安装器。
旧 `inc2l.exe` 在 Windows Server 2022 上报 `0xC0000005`，因此 Windows API 导入库使用 runner 已安装的 Windows SDK x86 版本，MASM32 宏、头文件和运行库源码保持原样。
SDK 放在仓库所在盘的 `\masm32`（已有目录则拒绝覆盖），满足原始源码的绝对路径引用。构建上传 `windows-x86-masm-markers.zip`，根目录包含 `Project1.exe` 和 `VMProtectSDK32.dll`。

VB6 使用第三方归档 [sdksmate/vb6-portable](https://github.com/sdksmate/vb6-portable/tree/01ecb4d13e5ec00c8986dfec86dce46f923a4f3b)，固定 commit `01ecb4d13e5ec00c8986dfec86dce46f923a4f3b`，ZIP SHA-256 为 `7d58685bd0b6c6313a5c95200e9250d15288aae47bd124189dcf6f98fd9c9576`。
[`install-vb6.ps1`](ci/install-vb6.ps1) 每次校验下载或缓存的 ZIP，将包内全部文件解压到 `.build/vb6/`（去掉 ZIP 最外层目录），用 32 位进程注册 VBA6 / VB6 类型库；直接调用 `VB6.exe`，不运行包内便携启动器或注册表安装器。工具链的版权及许可仍归原权利人所有。
脚本还重放 [VB98ENT.STF 的 Core 注册项](https://github.com/gdsestimating/vb6-install-recipe/blob/70ef8f17ce744b9affadf044b3e2e68a7846570f/vb98ent_minimal.stf#L726-L728)；只解压文件会使编译器报 `No make available in the Working Model Edition`。
脚本通过 PowerShell 调用 `msiexec /i ... /qn /norestart ADDLOCAL=ALL`，静默安装完整的微软官方 [KB2708437 更新包](https://www.microsoft.com/en-us/download/details.aspx?id=30505)，由 Windows Installer 安装并注册组件，包括 portable 包缺少的 `MSSTDFMT.DLL`。MSI 的 SHA-256 固定为 `350602b2e084b39c97d1394c8594b18e41ef622315d4a9635c5e8ea6aa977b5e`。安装接受退出码 `0` 和 `3010`，后者会提示需要重启，但不自动重启 runner。
此 MSI 默认要求已安装 VB6 SP6，否则返回 `1603`。portable 没有安装记录，因此脚本显式传入 `VB6PRODUCTDIR`、`VB6COMMONDIR` 和 `VB6SP6REGKEY="#6"`，跳过其 SP6 安装记录检查；不写入虚假的系统 SP6 注册项。更新包仅安装控件，编译器仍为 `6.00.8176`。
即使没有数据库绑定，VB6 编译带 `TextBox` / `Label` 的窗体仍需要这个组件；缺失时 VB6 6.00.8176 会以 `0xC0000005` 崩溃。注册代码直接传给 32 位 PowerShell 执行，不生成额外脚本文件。
两个工程按原始编译选项构建，不修改 `.vbp`、窗体或 SDK。每个工程限时 120 秒，同时检查进程退出码、成功日志和非空 EXE；缺少工具链或编译失败会使 job 失败。
VB6 分别上传 `windows-x86-vb6-markers.zip` 和 `windows-x86-vb6-licensing.zip`。根目录包含各自的 `Project1.exe` 或 `TestApp.exe`，以及 `VMProtectSDK32.dll`。

BCB 和 Delphi 共用 Embarcadero 官方 RAD Studio XE5 Update 2 的 [Win32 组件包](https://altd.embarcadero.com/release/radstudio/12.0/DB629168-0140-4C2D-9E68-79614F3D3B4E/bcbwin32.7zip)。
完整的搜寻、下载地址来源、密码解码、组件定位、解包映射和验证过程见 [RAD Studio XE5 工具链复现记录](docs/radstudio-xe5-toolchain-discovery.md)。
[`install-radstudio-xe5.ps1`](ci/install-radstudio-xe5.ps1) 下载清单中的全部 10 个原始组件，合计约 132 MiB，逐包校验长度和 SHA-256，使用 runner 自带的 7-Zip 解包到 `.build/radstudio-xe5/`。缓存命中仍执行摘要校验。
[`radstudio-xe5-toolchain.json`](ci/radstudio-xe5-toolchain.json) 记录固定版本的下载地址、摘要、归档密码和目录映射；密码与目录映射来自官方 [XE5 Update 2 离线介质](https://altd.embarcadero.com/download/radstudio/xe5/delphicbuilder_xe5_upd2_win.iso) 中的 `Install/Setup.exe`，其 SHA-256 为 `300000b70e29b5b180b449331a6a72d2d90999ed2e3d9e9b8895acef67e1fb4b`。
完整离线介质为 4.82 GiB；CI 仅准备 Win32 命令行工具、头文件和库，不安装 IDE，不修改工具二进制。工具链版权及许可仍归 Embarcadero 所有。
Delphi 编译器来自 `transmogrifierd` 组件包，使用 `lib/win32/release` 中的配套 RTL/VCL。命令行通过 `-NSSystem;Winapi;Vcl` 解析旧源码中的单元名，通过 `-N0` 将 DCU 输出到独立中间目录。
构建不转换 `.dof` / `.dproj`。Licensing 的原 `.dpr` 引用了缺失的 `TestApp.res`，CI 仅在构建副本生成空资源。新 EXE、MAP 和中间文件输出到独立目录，保留原有 `TestApp.map`。KeyGen 调用示例使用原包的 `KeyGen32.dll`，运行时检查空产品参数对应的 `Error: 2`。
三个项目分别上传 `windows-x86-delphi-markers.zip`、`windows-x86-delphi-licensing.zip` 和 `windows-x86-delphi-keygen-usage.zip`；根目录包含各自的 EXE、MAP 和所需的 `VMProtectSDK32.dll` 或 `KeyGen32.dll`。

BCB Code Markers 工程来自 BCB6，Licensing 使用 XE5 的 Unicode VCL。两者统一使用 `bcc32` 6.70 / `ilink32` 6.51 编译原始源码，不升级 `.bpr` / `.cbproj`。链接原 `.res`，保留图标、版本信息和嵌入的应用 manifest；Licensing 沿用 Unicode 入口点，通过命令行补充 `Include/C` 搜索路径。
原包的 `VMProtectSDK32.lib` 是 COFF 格式；CI 用官方 `implib.exe` 从原 DLL 在独立中间目录生成 OMF 库，并保持原 COFF 文件及链接不变。DFM 仅复制到中间目录供链接器读取。
VCL 和 C/C++ RTL 静态链接，使用兼容 Delphi 异常的 `cp32mt.lib`；使用 `cw32mt.lib` 会导致 Licensing 启动时异常终止。每个项目分别上传 `windows-x86-bcb-markers.zip` 或 `windows-x86-bcb-licensing.zip`，根目录包含各自的 EXE、MAP、TDS 和 `VMProtectSDK32.dll`。生成的导入库、OBJ、DFM 副本和响应文件均不打包。
[`smoke-vcl.ps1`](ci/smoke-vcl.ps1) 通过 `-Kind bcb` 或 `-Kind delphi` 从产物目录启动对应程序，要求 15 秒内出现原 DFM 指定标题的主窗口，然后正常关闭并检查退出码；仅清理本轮启动的进程。

DDK 使用微软官方 WDK 7.1.0（7600.16385.1）。[`install-wdk71.ps1`](ci/install-wdk71.ps1) 下载并缓存完整 ISO，校验长度和 SHA-256，再以 Windows Installer 静默全量安装构建工具、头文件、x86 库和 XP 库这四个 MSI 组件。
安装到原 `make.bat` 指定的 `C:\WinDDK\7600.16385.1`，在构建副本执行原批处理，由配套的 NMAKE、CL 和 LINK 编译原始驱动源码。
[`build-ddk.ps1`](ci/build-ddk.ps1) 拒绝旧输出，要求新生成 SYS、MAP 和 PDB，并核对 x86、Native 子系统及 `VMProtectDDK32.sys` / `ntoskrnl.exe` 导入。
产物为 `windows-x86-ddk-licensing.zip`，根目录包含 `TestApp.sys`、`VMProtectDDK32.sys`、`TestApp.map` 和 `TestApp.pdb`。CI 验证编译、链接和打包，不加载内核驱动，不执行驱动签名或授权流程。
工具链来源、安装参数、远程验证和链接存档结果见 [Licensing DDK 构建记录](docs/licensing-ddk-build.md)。

### 未纳入标准 runner 的项目

这些文件完整保留，未用跳过或 `continue-on-error` 冒充构建通过：

- Examples/Scripts：保留原预编译程序及 `.vmp` 配置；没有相应程序源码，无法重新编译。
- KeyGen/PHP：解释执行示例，无编译目标。

## 本地构建与验证

```bash
python3 ci/verify.py
python3 ci/prepare.py
# Linux：预先安装 g++-multilib、g++-mingw-w64-i686
bash ci/build-unix.sh linux
python3 ci/verify.py --root .build/work --build-tree
python3 ci/package.py linux-x64-gcc-markers
```

macOS 使用 `gcc`、`fpc`、`xcode-markers` 或 `xcode-licensing` 参数。需要 Intel Mac；本包的 Mach-O SDK 只有 i386/x86_64，没有 ARM64。
Windows 使用 `./ci/build-windows.ps1 -Kind native -Arch x86`，或 `masm` / `vb6` / `bcb` / `delphi` / `ddk` / `managed` / `pascal`；环境准备见 workflow。
MASM 只支持 x86：准备 7-Zip 后运行 `./ci/install-masm32.ps1`，再运行 `python ci/prepare.py` 和 `./ci/build-windows.ps1 -Kind masm -Arch x86`。
VB6 只支持 x86：在 Windows x64 / PowerShell 7.4+ 环境运行 `./ci/install-vb6.ps1`，再运行 `python ci/prepare.py` 和 `./ci/build-windows.ps1 -Kind vb6 -Arch x86`。安装 MSI 和注册组件需要管理员权限；GitHub Windows runner 已具备该权限。
BCB 和 Delphi 只支持 x86：在 Windows / PowerShell 7 环境准备 7-Zip，运行 `./ci/install-radstudio-xe5.ps1`，再运行 `python ci/prepare.py` 和 `./ci/build-windows.ps1 -Kind bcb -Arch x86` 或 `-Kind delphi -Arch x86`。
DDK 原工程只配置 x86：在 Windows / PowerShell 7 环境准备 7-Zip，以管理员权限运行 `./ci/install-wdk71.ps1`，再运行 `python ci/prepare.py` 和 `./ci/build-windows.ps1 -Kind ddk -Arch x86`。

参考：[GitHub runner 标签](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)、[Windows 2022 工具清单](https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md)、[Free Pascal 下载](https://www.freepascal.org/download.html)。

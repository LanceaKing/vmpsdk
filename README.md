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
所有构建使用 `.build/work/` 中的副本，产物放在 `.build/artifacts/` 并上传至 Actions artifacts。
构建前后校验全部导入文件；构建副本也校验原始文件摘要。源文件、工程及 SDK 不打补丁、不重写、不自动升级。

使用 [`actions/cache`](https://github.com/actions/cache) 缓存 Linux 编译器安装包、macOS FPC 下载文件、Windows MASM32 / VB6 工具链下载包、.NET 引用程序集和 Lazarus/FPC 安装目录。
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
| Windows 2022 | KeyGen DLL 和调用示例，x86 / x64 | 按旧 `.vcproj` 的源文件、资源与 `.def` 构建；原工程无需转换 |
| Windows 2022 | .NET Code Markers / Licensing / KeyGen / Usage | 原 `.csproj`，NuGet reference assemblies 保留 v2.0 / v4.0 目标框架，命令行补齐引用路径 |
| Windows 2022 | Free Pascal / Lazarus Code Markers，x86 | Lazarus 4.0 / FPC 3.2.2；FPC 沿用 `makeit.bat` 参数；Lazarus 使用原源文件及预编译 LCL units |

GUI 示例只验证编译和链接，不自动点击窗口。KeyGen 调用示例使用原有空产品参数，因此运行输出错误码是示例的预期行为，不能视为实际签发验证。
这里构建的是未保护示例，不执行 VMProtect 加壳，也不证明授权服务或保护后的程序行为。

兼容参数也仅限 CI：MinGW 在外部 include 目录建立 `Resource.h` → 原 `resource.h` 的别名，以适配 Linux 大小写规则；KeyGen DLL 用 MSVC `/FIstring` 补充旧 STL 曾间接包含的标准头文件。

MASM 使用 [CodingCrew 的 MASM32 v9 安装包](https://www.codingcrew.de/masm32/download/m32v9r.zip)，SHA-256 固定为 `000a660fce59e619ea608a889b9ae1e43ad1dfcb81ef79ca22a0d67503cd0205`。
[`install-masm32.ps1`](ci/install-masm32.ps1) 校验下载或缓存的安装包，用 runner 自带的 7-Zip 提取 `install.exe` 内嵌的数据，并编译 MASM32 静态库；不运行交互式安装器。
旧 `inc2l.exe` 在 Windows Server 2022 上报 `0xC0000005`，因此 Windows API 导入库使用 runner 已安装的 Windows SDK x86 版本，MASM32 宏、头文件和运行库源码保持原样。
SDK 放在仓库所在盘的 `\masm32`（已有目录则拒绝覆盖），满足原始源码的绝对路径引用。构建上传 `windows-masm-x86` artifact，内含 `masm-x86/Project1.exe` 和 `VMProtectSDK32.dll`。

VB6 使用第三方归档 [sdksmate/vb6-portable](https://github.com/sdksmate/vb6-portable/tree/01ecb4d13e5ec00c8986dfec86dce46f923a4f3b)，固定 commit `01ecb4d13e5ec00c8986dfec86dce46f923a4f3b`，ZIP SHA-256 为 `7d58685bd0b6c6313a5c95200e9250d15288aae47bd124189dcf6f98fd9c9576`。
[`install-vb6.ps1`](ci/install-vb6.ps1) 每次校验下载或缓存的 ZIP，将包内全部文件解压到 `.build/vb6/`（去掉 ZIP 最外层目录），用 32 位进程注册 VBA6 / VB6 类型库；直接调用 `VB6.exe`，不运行包内便携启动器或注册表安装器。工具链的版权及许可仍归原权利人所有。
脚本还重放 [VB98ENT.STF 的 Core 注册项](https://github.com/gdsestimating/vb6-install-recipe/blob/70ef8f17ce744b9affadf044b3e2e68a7846570f/vb98ent_minimal.stf#L726-L728)；只解压文件会使编译器报 `No make available in the Working Model Edition`。
脚本通过 PowerShell 调用 `msiexec /i ... /qn /norestart ADDLOCAL=ALL`，静默安装完整的微软官方 [KB2708437 更新包](https://www.microsoft.com/en-us/download/details.aspx?id=30505)，由 Windows Installer 安装并注册组件，包括 portable 包缺少的 `MSSTDFMT.DLL`。MSI 的 SHA-256 固定为 `350602b2e084b39c97d1394c8594b18e41ef622315d4a9635c5e8ea6aa977b5e`。安装接受退出码 `0` 和 `3010`，后者会提示需要重启，但不自动重启 runner。
即使没有数据库绑定，VB6 编译带 `TextBox` / `Label` 的窗体仍需要这个组件；缺失时 VB6 6.00.8176 会以 `0xC0000005` 崩溃。注册代码直接传给 32 位 PowerShell 执行，不生成额外脚本文件。
两个工程按原始编译选项构建，不修改 `.vbp`、窗体或 SDK。每个工程限时 120 秒，同时检查进程退出码、成功日志和非空 EXE；缺少工具链或编译失败会使 job 失败。
`windows-vb6-x86` artifact 包含 `markers-vb6-x86/Project1.exe`、`licensing-vb6-x86/TestApp.exe` 及各自的 `VMProtectSDK32.dll`。MSI 安装日志 `runtime-install.log` 和编译日志单独上传为 `windows-vb6-x86-logs`，失败时也保留。

### 未纳入标准 runner 的项目

这些文件完整保留，未用跳过或 `continue-on-error` 冒充构建通过：

- Delphi、BCB：需要相应编译器、VCL/运行库及许可环境。
- Licensing/DDK：原 `make.bat` 依赖 `C:\WinDDK\7600.16385.1` 和 XP 构建环境。
- Examples/Scripts：保留原预编译程序及 `.vmp` 配置；没有相应程序源码，无法重新编译。
- KeyGen/PHP：解释执行示例，无编译目标。

## 本地构建与验证

```bash
python3 ci/verify.py
python3 ci/prepare.py
# Linux：预先安装 g++-multilib、g++-mingw-w64-i686
bash ci/build-unix.sh linux
python3 ci/verify.py --root .build/work --build-tree
```

macOS 使用 `gcc`、`fpc`、`xcode-markers` 或 `xcode-licensing` 参数。需要 Intel Mac；本包的 Mach-O SDK 只有 i386/x86_64，没有 ARM64。
Windows 使用 `./ci/build-windows.ps1 -Kind native -Arch x86`，或 `masm` / `vb6` / `managed` / `pascal`；环境准备见 workflow。
MASM 只支持 x86：准备 7-Zip 后运行 `./ci/install-masm32.ps1`，再运行 `python ci/prepare.py` 和 `./ci/build-windows.ps1 -Kind masm -Arch x86`。
VB6 只支持 x86：在 Windows x64 / PowerShell 7.4+ 环境运行 `./ci/install-vb6.ps1`，再运行 `python ci/prepare.py` 和 `./ci/build-windows.ps1 -Kind vb6 -Arch x86`。安装 MSI 和注册组件需要管理员权限；GitHub Windows runner 已具备该权限。

参考：[GitHub runner 标签](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)、[Windows 2022 工具清单](https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md)、[Free Pascal 下载](https://www.freepascal.org/download.html)。

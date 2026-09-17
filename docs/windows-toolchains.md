# Windows 工具链

本文记录 Windows 示例使用的工具链、安装来源、兼容处理及产物检查。

本地构建命令和完整构建矩阵见 [构建与验证](building.md)。

## MASM32

MASM 使用 [CodingCrew 的 MASM32 v9 安装包](https://www.codingcrew.de/masm32/download/m32v9r.zip)，SHA-256 固定为 `000a660fce59e619ea608a889b9ae1e43ad1dfcb81ef79ca22a0d67503cd0205`。

[`install-masm32.ps1`](../ci/install-masm32.ps1) 校验下载或缓存的安装包，用 runner 自带的 7-Zip 提取 `install.exe` 内嵌的数据，并编译 MASM32 静态库。不运行交互式安装器。

旧 `inc2l.exe` 在 Windows Server 2022 上报 `0xC0000005`，因此 Windows API 导入库使用 runner 已安装的 Windows SDK x86 版本，MASM32 宏、头文件和运行库源码保持原样。

SDK 放在仓库所在盘的 `\masm32`（已有目录则拒绝覆盖），满足原始源码的绝对路径引用。构建上传 `windows-x86-masm-markers.zip`，根目录包含 `Project1.exe` 和 `VMProtectSDK32.dll`。

## Visual Basic 6

VB6 使用第三方归档 [sdksmate/vb6-portable](https://github.com/sdksmate/vb6-portable/tree/01ecb4d13e5ec00c8986dfec86dce46f923a4f3b)，固定 commit `01ecb4d13e5ec00c8986dfec86dce46f923a4f3b`，ZIP SHA-256 为 `7d58685bd0b6c6313a5c95200e9250d15288aae47bd124189dcf6f98fd9c9576`。

[`install-vb6.ps1`](../ci/install-vb6.ps1) 每次校验下载或缓存的 ZIP，将包内全部文件解压到 `.build/vb6/`（去掉 ZIP 最外层目录），用 32 位进程注册 VBA6 / VB6 类型库。直接调用 `VB6.exe`，不运行包内便携启动器或注册表安装器。工具链的版权及许可仍归原权利人所有。

脚本还重放 [VB98ENT.STF 的 Core 注册项](https://github.com/gdsestimating/vb6-install-recipe/blob/70ef8f17ce744b9affadf044b3e2e68a7846570f/vb98ent_minimal.stf#L726-L728)。只解压文件会使编译器报 `No make available in the Working Model Edition`。

脚本通过 PowerShell 调用 `msiexec /i ... /qn /norestart ADDLOCAL=ALL`，静默安装完整的微软官方 [KB2708437 更新包](https://www.microsoft.com/en-us/download/details.aspx?id=30505)，由 Windows Installer 安装并注册组件，包括 portable 包缺少的 `MSSTDFMT.DLL`。MSI 的 SHA-256 固定为 `350602b2e084b39c97d1394c8594b18e41ef622315d4a9635c5e8ea6aa977b5e`。安装接受退出码 `0` 和 `3010`，后者会提示需要重启，但不自动重启 runner。

此 MSI 默认要求已安装 VB6 SP6，否则返回 `1603`。portable 没有安装记录，因此脚本显式传入 `VB6PRODUCTDIR`、`VB6COMMONDIR` 和 `VB6SP6REGKEY="#6"`，跳过其 SP6 安装记录检查。不写入虚假的系统 SP6 注册项。更新包仅安装控件，编译器仍为 `6.00.8176`。

即使没有数据库绑定，VB6 编译带 `TextBox` / `Label` 的窗体仍需要这个组件。缺失时 VB6 6.00.8176 会以 `0xC0000005` 崩溃。注册代码直接传给 32 位 PowerShell 执行，不生成额外脚本文件。

两个工程按原始编译选项构建，不修改 `.vbp`、窗体或 SDK。每个工程限时 120 秒，同时检查进程退出码、成功日志和非空 EXE。缺少工具链或编译失败会使 job 失败。

VB6 分别上传 `windows-x86-vb6-markers.zip` 和 `windows-x86-vb6-licensing.zip`。根目录包含各自的 `Project1.exe` 或 `TestApp.exe`，以及 `VMProtectSDK32.dll`。

## RAD Studio XE5：BCB 与 Delphi

### 共用工具链

BCB 和 Delphi 共用 Embarcadero 官方 RAD Studio XE5 Update 2 的 [Win32 组件包](https://altd.embarcadero.com/release/radstudio/12.0/DB629168-0140-4C2D-9E68-79614F3D3B4E/bcbwin32.7zip)。

完整的搜寻、下载地址来源、密码解码、组件定位、解包映射和验证过程见 [RAD Studio XE5 工具链复现记录](radstudio-xe5-toolchain-discovery.md)。

[`install-radstudio-xe5.ps1`](../ci/install-radstudio-xe5.ps1) 下载清单中的全部 10 个原始组件，合计约 132 MiB，逐包校验长度和 SHA-256，使用 runner 自带的 7-Zip 解包到 `.build/radstudio-xe5/`。缓存命中仍执行摘要校验。

[`radstudio-xe5-toolchain.json`](../ci/radstudio-xe5-toolchain.json) 记录固定版本的下载地址、摘要、归档密码和目录映射。密码与目录映射来自官方 [XE5 Update 2 离线介质](https://altd.embarcadero.com/download/radstudio/xe5/delphicbuilder_xe5_upd2_win.iso) 中的 `Install/Setup.exe`，其 SHA-256 为 `300000b70e29b5b180b449331a6a72d2d90999ed2e3d9e9b8895acef67e1fb4b`。

完整离线介质为 4.82 GiB。CI 仅准备 Win32 命令行工具、头文件和库，不安装 IDE，不修改工具二进制。工具链版权及许可仍归 Embarcadero 所有。

### Delphi

Delphi 编译器来自 `transmogrifierd` 组件包，使用 `lib/win32/release` 中的配套 RTL/VCL。命令行通过 `-NSSystem;Winapi;Vcl` 解析旧源码中的单元名，通过 `-N0` 将 DCU 输出到独立中间目录。

构建不转换 `.dof` / `.dproj`。Licensing 的原 `.dpr` 引用了缺失的 `TestApp.res`，CI 仅在构建副本生成空资源。新 EXE、MAP 和中间文件输出到独立目录，保留原有 `TestApp.map`。KeyGen 调用示例使用原包的 `KeyGen32.dll`，运行时检查空产品参数对应的 `Error: 2`。

三个项目分别上传 `windows-x86-delphi-markers.zip`、`windows-x86-delphi-licensing.zip` 和 `windows-x86-delphi-keygen-usage.zip`。根目录包含各自的 EXE、MAP 和所需的 `VMProtectSDK32.dll` 或 `KeyGen32.dll`。

### C++Builder

BCB Code Markers 工程来自 BCB6，Licensing 使用 XE5 的 Unicode VCL。两者统一使用 `bcc32` 6.70 / `ilink32` 6.51 编译原始源码，不升级 `.bpr` / `.cbproj`。链接原 `.res`，保留图标、版本信息和嵌入的应用 manifest。Licensing 沿用 Unicode 入口点，通过命令行补充 `Include/C` 搜索路径。

原包的 `VMProtectSDK32.lib` 是 COFF 格式。CI 用官方 `implib.exe` 从原 DLL 在独立中间目录生成 OMF 库，并保持原 COFF 文件及链接不变。DFM 仅复制到中间目录供链接器读取。

VCL 和 C/C++ RTL 静态链接，使用兼容 Delphi 异常的 `cp32mt.lib`。使用 `cw32mt.lib` 会导致 Licensing 启动时异常终止。每个项目分别上传 `windows-x86-bcb-markers.zip` 或 `windows-x86-bcb-licensing.zip`，根目录包含各自的 EXE、MAP、TDS 和 `VMProtectSDK32.dll`。生成的导入库、OBJ、DFM 副本和响应文件均不打包。

### 窗口验证

[`smoke-vcl.ps1`](../ci/smoke-vcl.ps1) 通过 `-Kind bcb` 或 `-Kind delphi` 从产物目录启动对应程序，要求 15 秒内出现原 DFM 指定标题的主窗口，然后正常关闭并检查退出码。仅清理本轮启动的进程。

## WDK 7.1：DDK

DDK 使用微软官方 WDK 7.1.0（7600.16385.1）。[`install-wdk71.ps1`](../ci/install-wdk71.ps1) 下载并缓存完整 ISO，校验长度和 SHA-256，再以 Windows Installer 静默全量安装构建工具、头文件、x86 库和 XP 库这四个 MSI 组件。

安装到原 `make.bat` 指定的 `C:\WinDDK\7600.16385.1`，在构建副本执行原批处理，由配套的 NMAKE、CL 和 LINK 编译原始驱动源码。

[`build-ddk.ps1`](../ci/build-ddk.ps1) 拒绝旧输出，要求新生成 SYS、MAP 和 PDB，并核对 x86、Native 子系统及 `VMProtectDDK32.sys` / `ntoskrnl.exe` 导入。

产物为 `windows-x86-ddk-licensing.zip`，根目录包含 `TestApp.sys`、`VMProtectDDK32.sys`、`TestApp.map` 和 `TestApp.pdb`。CI 验证编译、链接和打包，不加载内核驱动，不执行驱动签名或授权流程。

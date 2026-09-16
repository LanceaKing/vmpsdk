# Licensing/DDK 的 GitHub Actions 构建记录

记录日期：2026-09-17。任务目标是在 GitHub Actions 上构建原始 `Examples/Licensing/DDK` 示例，并按仓库约定上传独立 ZIP。两次 Windows runner 实测均完成编译、链接、完整性检查和 ZIP 上传，分别验证缓存写入和恢复；使用 WDK 7.1.0 构建 x86 Windows XP free 目标。

本次工作从提交 [`461915e`](https://github.com/LanceaKing/vmpsdk/commit/461915ec249ffa6e0bd5c50f32b42d67eee4f8c9) 开始。原始示例、工程、SDK 头文件和库均保持不变；构建在 `.build/work/` 副本中进行。本文由独立的过程记录分支聊天整理，主聊天提供实际操作、证据和验证结果，并在交付前核对。

## 1. 从原始工程确认需求

直接检查了以下文件：

| 原始文件 | 确认的内容 |
| --- | --- |
| [`make.bat`](../Examples/Licensing/DDK/make.bat) | `DDK_PATH=C:\WinDDK\7600.16385.1\`，调用 `setenv.bat`，参数为 `wxp free no_oacr`，然后执行 `nmake` |
| [`MAKEFILE`](../Examples/Licensing/DDK/MAKEFILE) | 包含 `$(NTMAKEENV)\makefile.def`，依赖 DDK 的构建规则 |
| [`SOURCES`](../Examples/Licensing/DDK/SOURCES) | `TARGETNAME=TestApp`、`TARGETTYPE=DRIVER`、`TARGETPATH=bin`、`TARGETLIBS=VMProtectDDK32.lib`、`SOURCES=TestApp.c`，链接时生成 MAP |
| [`TestApp.c`](../Examples/Licensing/DDK/TestApp.c) | 包含 `ntddk.h` 和 `VMProtectDDK.h`；定义 `DriverEntry` / `DriverUnload`，调用内核池分配、`DbgPrint` 以及 VMProtect 授权 API |

因此原始入口是 WDK 7.1.0 的 Windows XP free 构建环境，链接的是 32 位 `VMProtectDDK32.lib`。单纯让 MSVC 编译一个普通 EXE 无法覆盖这个工程的驱动构建需求。

验收需要分别记录编译链接、原始字节完整性、产物结构与依赖检查。成功生成 SYS 本身不证明驱动已安装、加载或通过授权逻辑验证。

## 2. 工具链搜寻与方案选择

先通过 Context7 的 `/microsoftdocs/windows-driver-docs` 查询驱动构建资料，再打开微软原始页面核对。微软的 [WDK known issues](https://learn.microsoft.com/en-us/windows-hardware/drivers/wdk-known-issues) 明确说明：从 Windows 11 24H2 WDK 起，不再支持 x86 内核驱动开发。这个事实排除了直接套用最新 WDK 的方案，但不证明其他旧 WDK 不兼容；本次优先选择原 `make.bat` 指定的 7.1.0，避免先转换原工程。

[微软 WDK 7.1.0 下载页](https://www.microsoft.com/en-us/download/details.aspx?id=11800) 列出 `GRMWDK_EN_7600_1.ISO`，页面显示大小 619.8 MB，并说明此版包含用于 Windows XP 等系统的编译器、头文件和库。下载链接直接指向微软下载域名，而不是从第三方重新打包取得：

```text
https://download.microsoft.com/download/4/A/2/4A25C7D5-EFBE-4182-B6A9-AE6850409A78/GRMWDK_EN_7600_1.ISO
```

实际下载命令：

```bash
mkdir -p .build/downloads/wdk-7.1
curl -fL --retry 3 \
  --output .build/downloads/wdk-7.1/GRMWDK_EN_7600_1.ISO \
  'https://download.microsoft.com/download/4/A/2/4A25C7D5-EFBE-4182-B6A9-AE6850409A78/GRMWDK_EN_7600_1.ISO'
```

完整下载后，用 Python 流式读取重新核对得到：

| 项目 | 值 |
| --- | --- |
| 文件长度 | `649877504` 字节 |
| SHA-256 | `5edc723b50ea28a070cad361dd0927df402b7a861a036bbcf11d27ebba77657d` |
| ISO 卷标 | `WDK` |
| ISO 目录创建时间 | `2010-02-19 08:00:00.00` |

这是本次从微软下载文件后计算的 SHA-256，不把下载页面显示的日期或大小当作摘要来源。本地研究使用 macOS ARM64 的 7-Zip 25.01；完整介质解包日志为 `Everything is Ok`。

本次目标先限定为原工程的 x86 驱动。虽然 SDK 同时提供 64 位库，原 `SOURCES` 固定链接 `VMProtectDDK32.lib`；不能用 64 位工具链生成文件后仍称为原工程的 x86 验证。

## 3. 实现与复现命令

### 3.1 从 ISO 安装匹配的组件

先在本地查看 ISO 目录和 SKOM 包装清单，确认 Windows Installer 参数。每个 `SKOMs/SKOM_4-packaging-<包名>.xml` 的 `CommandLine` 都记录了 `SOURCEINSTALL=1` 和 `DEFAULT_INSTALL_DIR1="$(INSTALLATION_PATH)"`。因此安装目录属性来自原始介质，不是试猜的通用 MSI 属性。

[`ci/install-wdk71.ps1`](../ci/install-wdk71.ps1) 使用四个组件及其外置 CAB：

| 包名 | MSI 字节数 | CAB 字节数 | 用途 |
| --- | ---: | ---: | --- |
| `buildtools_x86fre` | 135168 | 18687841 | x86 构建工具、编译器、链接器和 DDK 构建规则 |
| `headers` | 227840 | 6821830 | 包括 `ntddk.h` 的头文件 |
| `libs_x86fre` | 163840 | 30488176 | x86 通用库 |
| `wxplibs_x86fre` | 155136 | 8014325 | Windows XP x86 内核库 |

文件在 ISO 内的映射为 `WDK/<包名>.msi` 和 `WDK/<包名>_cab001.cab`，提取后保留这一层目录。无需解码或解密；7-Zip 直接读取 ISO 文件系统。研究阶段额外查看过 `buildtools_x64fre`，它没有进入正式安装清单。

每个组件均小于 200 MB，正式 CI 调用安装器静默全量安装这些组件，使用 `ADDLOCAL=ALL`，没有把 CAB 手工展开后冒充安装。这里的“全量”指选定的每个 MSI 组件；没有安装 ISO 的其他架构、文档、样例和调试器。

等价的单组件安装命令为：

```powershell
msiexec.exe /i ".build\wdk71-media\WDK\buildtools_x86fre.msi" `
  /qn /norestart ADDLOCAL=ALL SOURCEINSTALL=1 `
  DEFAULT_INSTALL_DIR1="C:\WinDDK\7600.16385.1" `
  /l*v ".build\logs\wdk71\buildtools_x86fre.log"
```

安装脚本完成以下检查：

1. `C:\WinDDK\7600.16385.1` 已存在时停止，避免覆盖已有工具链。
2. 无缓存时下载完整 ISO；无论下载还是恢复缓存，都检查固定长度及 SHA-256。
3. 用 runner 自带的 7-Zip 提取四个 MSI 及四个 CAB。
4. 顺序执行四次 MSI 安装，接受退出码 `0` 或 `3010`；后者记录需要重启，但不自动重启 runner。其他退出码打印安装日志末尾并使 job 失败。
5. 检查 `setenv.bat`、`makefile.def`、`nmake.exe`、x86 `cl.exe` / `link.exe`、`ntddk.h` 及 `lib/wxp/i386/ntoskrnl.lib`。

缓存保存的是原始 ISO，不是已安装目录。键包含 runner 平台、架构、`windows-2022`、WDK 版本和安装脚本摘要。缓存命中后仍校验并重新安装，只有下载被跳过。

### 3.2 使用原始构建入口

[`ci/build-windows.ps1`](../ci/build-windows.ps1) 增加 `-Kind ddk -Arch x86` 入口，并在进入 Visual Studio 环境之前转交 [`ci/build-ddk.ps1`](../ci/build-ddk.ps1)。DDK 模式拒绝 `-Arch x64`。

驱动脚本在 `.build/work/Examples/Licensing/DDK` 执行 `cmd.exe /d /c "call make.bat"`。原 `make.bat` 设置 WDK 环境并执行 `nmake`；原 `MAKEFILE`、`SOURCES`、`TestApp.c` 和 SDK 头文件/库保持不变。脚本先拒绝已有目标目录或残留 SYS / MAP / PDB，构建后要求这三个输出各有一个且非空。

输出复制到 `.build/artifacts/licensing-ddk-x86/`。用 WDK 自带的 `link.exe /dump /headers /imports` 检查 `TestApp.sys` 为 `14C machine (x86)`、`1 subsystem (Native)`，并导入 `VMProtectDDK32.sys` 和 `ntoskrnl.exe`；若发现 `kernel32.dll`、`user32.dll`、`msvcrt.dll` 或 `VMProtectSDK32.dll` 等用户态依赖，则失败。

Windows 管理员环境准备 7-Zip 和 Python 后，可从仓库根目录复现：

```powershell
python ci/verify.py
./ci/install-wdk71.ps1
python ci/prepare.py
./ci/build-windows.ps1 -Kind ddk -Arch x86
python ci/verify.py
python ci/verify.py --root .build/work --build-tree
python ci/package.py windows-x86-ddk-licensing
```

### 3.3 独立项目 ZIP

[`build.yml`](../.github/workflows/build.yml) 新增 `Windows / ddk / x86`，runner 为 `windows-2022`。构建后的完整性检查和 [统一打包 action](../.github/actions/package-project/action.yml) 沿用其他示例的入口。

[`ci/package.py`](../ci/package.py) 定义 `windows-x86-ddk-licensing.zip`，根目录必须包含以下四项：

```text
TestApp.sys
TestApp.map
TestApp.pdb
VMProtectDDK32.sys
```

`VMProtectDDK32.sys` 从原始 SDK 的 `Lib/Windows/` 复制，是驱动的运行依赖。OBJ、构建日志和安装介质不打包。上传保持 `archive: false`，直接提供项目 ZIP。

## 4. 失败尝试与修正

| 现象或错误 | 证据与处理 |
| --- | --- |
| 首次读取 ISO 报 `Unexpected end of archive` | 下载仍在进行时提前执行提取，`.build/ddk-research/extract-first.log` 当时只读到 `517943296` 字节，而 ISO 声明完整长度 `649877504`。等待同一次下载完成后重新提取，没有重新下载；`extract-complete.log` 记录 `Everything is Ok`。最终脚本先完成下载并校验长度与 SHA-256，再调用提取工具。 |

## 5. 本地与远程验证

第一版实现为提交 [`12fff1f`](https://github.com/LanceaKing/vmpsdk/commit/12fff1f)，位于 `codex/licensing-ddk-actions` 分支；它以仅更新既有 RAD Studio 文档的 `038cd2b` 为基线。

在本地 macOS 上完成以下检查：

| 检查 | 结果 |
| --- | --- |
| `python3 ci/verify.py` | 263 个原始文件/链接的摘要通过 |
| `python3 -m unittest discover -s ci -p 'test_*.py'` | 14 个打包测试通过，包括 DDK 四项精确文件清单和缺少内核运行依赖时拒绝打包 |
| `actionlint` 1.7.12 | workflow 检查通过 |
| PowerShell 7.6.6 语法解析 | 安装与构建脚本解析通过 |
| `git diff --check` | 通过 |

这些本地检查不执行 Windows MSI；实际驱动编译由以下 Windows runner 结果证明。

### 首次运行与缓存写入

[运行 35122513601 的 DDK job](https://github.com/LanceaKing/vmpsdk/actions/runs/35122513601/job/104883515004) 对应 `12fff1f`，DDK job 成功；[完整 workflow](https://github.com/LanceaKing/vmpsdk/actions/runs/35122513601) 共 14 个 job，全部成功。以下 DDK 结论来自该 job 的原始日志，本地副本为 `.build/ddk-research/cold-ddk.log`。

| 项目 | 实测结果 |
| --- | --- |
| runner | Windows Server 2022 `10.0.20348`，镜像 `20260907.297.1`，runner `2.337.0` |
| 安装 | 四个 MSI 均退出 `0` |
| 编译器 | Microsoft C/C++ `15.00.30729.207 for 80x86` |
| NMAKE / LINK | `9.00.30729.207` |
| 原入口构建 | 原 `make.bat` / `MAKEFILE` / `SOURCES` 编译链接通过 |
| PE 检查 | x86、Native 子系统，导入 `ntoskrnl.exe` 和 `VMProtectDDK32.sys` |
| 完整性 | 构建后原仓库及 `.build/work` 各自的 263 项摘要均通过 |
| 打包 | 四个文件均位于 ZIP 根目录，打包检查及上传通过 |

冷缓存日志先记录 `Cache not found for input keys`，随后下载并校验 ISO，job 结束时记录 `Cache saved with key`。缓存键为：

```text
Windows-X64-windows-2022-wdk-7.1-72c377eaae7ece8934c109815829cbafef76c4678e3711acb24e33ddebfd1717
```

### 下载 ZIP 核对

从本仓库的 [artifact 10457372881](https://github.com/LanceaKing/vmpsdk/actions/runs/35122513601/artifacts/10457372881) 下载 `windows-x86-ddk-licensing.zip` 后独立读取并验证：

- ZIP 长度为 **42403 字节**。
- SHA-256 为 `8630e177e40b05c3378cf9ed953eae6124531d63c1acf8ca46af51eca451524c`，与上传日志一致。
- `ZipFile.testzip()` 返回 `None`，全部成员 CRC 检查通过。
- 根目录恰好四项，没有 OBJ、日志或安装包。
- ZIP 中 `VMProtectDDK32.sys` 与仓库 `Lib/Windows/VMProtectDDK32.sys` 逐字节相同。
- 再用 Python `struct` 读取下载的 PE：Machine 为 `0x14c`、Subsystem 为 `1`、入口 RVA 为 `0xcbe`，导入模块恰好是 `ntoskrnl.exe` 和 `VMProtectDDK32.sys`。
- PDB 文件头为 MSF 7.00，MAP 中存在 `DriverEntry`。

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `TestApp.sys` | 3840 | `e13d6c2312edfd582aad65badc625ca64b20780e4ca594d9867a6789f43e0d5c` |
| `VMProtectDDK32.sys` | 3584 | `a60b454f466c059af28a7676d4f441f9c60e5d31c47d0aa3c8438778a8b90943` |
| `TestApp.map` | 5975 | `a4cfd16559ec93149fd10a41fa5adadbc85f56a9b2f94e555008f74ba5e1d451` |
| `TestApp.pdb` | 142336 | `32c37814364cda00c00a34d7aa19489fe4afb0da706f5b70da6f9b54374d3220` |

这些摘要标识首次构建产物，不要求后续构建的时间戳、PDB 标识和 ZIP 字节完全一致。

### 缓存恢复与验收范围

[第二次运行 35122905614](https://github.com/LanceaKing/vmpsdk/actions/runs/35122905614) 对应提交 [`ee63113`](https://github.com/LanceaKing/vmpsdk/commit/ee63113c28c685765cd09c870de464ec54c295c9)，完整矩阵 14/14 成功。[DDK job 104884821837](https://github.com/LanceaKing/vmpsdk/actions/runs/35122905614/job/104884821837) 的原始日志保存在本地 `.build/ddk-research/warm-ddk.log`。

日志明确记录 `Cache restored from key`，键与首次运行完全相同；随后记录 `Using cached WDK 7.1 ISO; skipping download and verifying its digest`。ISO 摘要再次通过，四个 MSI 全部退出 `0`，原入口重新编译成功，原仓库及构建副本各自的 263 项摘要通过，四项 ZIP 打包及上传成功。因此实际验证了跳过下载、保留摘要检查和重新安装/构建的缓存行为。

第二次 [artifact 10458287269](https://github.com/LanceaKing/vmpsdk/actions/runs/35122905614/artifacts/10458287269) 的 ZIP 为 **42399 字节**，SHA-256 为 `ebb03d05502f6c5c12764b04a4681cd8066f31521c04e3d88909640447d0fd28`。再次下载后，CRC、精确四项根目录清单、四个成员长度、x86 / Native PE、非零入口点、MAP 的 `DriverEntry`、PDB 的 MSF 7.00 文件头和原始 SDK 运行依赖逐字节比较均通过。

以下命令可重新下载并核对第二次运行的原始 ZIP。这里使用 `gh api` 的 `--allow-escape-sequences`，避免新版 GitHub CLI 对二进制输出中的转义字节进行阻断；输出重定向到文件，不向终端打印二进制：

```bash
mkdir -p .build/ddk-research
gh api repos/LanceaKing/vmpsdk/actions/artifacts/10458287269/zip \
  --allow-escape-sequences \
  > .build/ddk-research/windows-x86-ddk-licensing-warm.zip

python3 - <<'PY'
from pathlib import Path
import hashlib
import zipfile

p = Path('.build/ddk-research/windows-x86-ddk-licensing-warm.zip')
assert p.stat().st_size == 42399
assert hashlib.sha256(p.read_bytes()).hexdigest() == (
    'ebb03d05502f6c5c12764b04a4681cd8066f31521c04e3d88909640447d0fd28'
)
with zipfile.ZipFile(p) as archive:
    assert archive.testzip() is None
    assert set(archive.namelist()) == {
        'TestApp.sys', 'TestApp.map', 'TestApp.pdb', 'VMProtectDDK32.sys'
    }
    assert archive.read('VMProtectDDK32.sys') == Path(
        'Lib/Windows/VMProtectDDK32.sys'
    ).read_bytes()
print('PASS: downloaded ZIP, CRC, root file list, and original runtime')
PY
```

Actions artifact 有保留期限；若链接已过期，应重新运行同一提交并按文件结构及构建日志验证，不把新构建的 ZIP 摘要硬套为本次记录的摘要。

本次 CI 验证构建及静态产物结构，不安装或加载 SYS，不执行驱动授权逻辑，也不执行 VMProtect 加壳。GitHub 的 x64 Windows runner 负责运行 x86 编译工具；产物是 x86 内核驱动，这与 runner 的架构不同。

## 6. 外部链接存档

按 [复杂任务过程记录约定](complex-task-records.md)，本仓库的 GitHub 链接及仓库内相对链接免存档。其他实际采用的来源页面和下载地址将在本节逐一记录原地址、存档日期、提交结果及快照内容验证；未取得并核验快照的链接不标记完成。

存档尝试日期为 **2026-09-17（Asia/Shanghai）**；响应头使用 UTC，时间为 2026-09-16。对下面每个地址分别访问 Save Page Now 的 `/save/<原始 URL>` 同步入口，再通过 `/save/` POST `url=<原始 URL>`、`capture_all=on` 和 `Accept: application/json` 重试。

| 原始链接 | 同步提交 | POST 提交 | 快照 / 结果 |
| --- | --- | --- | --- |
| [WDK known issues](https://learn.microsoft.com/en-us/windows-hardware/drivers/wdk-known-issues) | HTTP 500；内部错误页面 | HTTP 401；需要登录 | 未取得快照 URL，**未完成** |
| [WDK 7.1.0 下载页](https://www.microsoft.com/en-us/download/details.aspx?id=11800) | HTTP 500；内部错误页面 | HTTP 401；需要登录 | 未取得快照 URL，**未完成** |
| [WDK 7.1.0 原始 ISO](https://download.microsoft.com/download/4/A/2/4A25C7D5-EFBE-4182-B6A9-AE6850409A78/GRMWDK_EN_7600_1.ISO) | HTTP 500；内部错误页面 | HTTP 401；需要登录 | 未取得快照 URL，**未完成** |

同步入口的正文为 `This snapshot cannot be displayed due to an internal error.`；POST 返回 `{"message":"You need to be logged in to use Save Page Now."}`。本次没有可用的 Internet Archive 登录会话或提交凭据，没有取得可以打开核验的快照，因而不能标记存档成功。原始响应头及正文保存在本地 `.build/ddk-research/archive/`，文件前缀为 `wdk-known-issues`、`wdk-download-page`、`wdk-iso`，分别带 `-save` 和 `-post` 后缀。

ISO 低于 2,000,000,000 字节的上传阈值，因此尝试的是 Save Page Now，未转为本地文件上传。

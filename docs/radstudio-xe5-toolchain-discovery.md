# RAD Studio XE5 工具链搜寻、密码提取与构建复现记录

记录日期：2026-09-16。对应正式实现提交：[`2314777`](https://github.com/LanceaKing/vmpsdk/commit/231477733c930a7978140513d22c28efb48e4d9e)。

本次工作从“在 GitHub Actions 构建 BCB 示例”开始，随后把 Delphi 示例也迁到同一套工具链。最终使用 **Embarcadero RAD Studio XE5 Update 2** 的原始组件包，在 `windows-2022` runner 上直接调用命令行工具。

本文记录当时的发现过程和可复现步骤。下载状态、文件大小、偏移和摘要均针对这个具体版本；其他版本需要重新核对。文中的“密码”指组件 `.7zip` 的解压密码，来自安装器内嵌数据。它与产品序列号、账号密码、激活信息不是同一种数据。

## 1. 最终保留的文件和工具

| 文件 | 用途 |
| --- | --- |
| [`ci/radstudio-xe5-toolchain.json`](../ci/radstudio-xe5-toolchain.json) | 下载基址、10 个已解码组件的包名、大小、密码、SHA-256、目录映射 |
| [`ci/install-radstudio-xe5.ps1`](../ci/install-radstudio-xe5.ps1) | 下载或读取缓存，校验、解包、按安装器映射组装工具链 |
| [`ci/build-windows.ps1`](../ci/build-windows.ps1) | BCB 和 Delphi 的编译、链接、输出检查 |
| [`ci/smoke-vcl.ps1`](../ci/smoke-vcl.ps1) | 在原生 Windows 上检查 BCB/Delphi 主窗体和正常退出 |
| [`ci/package.py`](../ci/package.py) | 每个项目的 ZIP 文件清单 |
| [`.github/workflows/build.yml`](../.github/workflows/build.yml) | 共用工具链安装、下载缓存及完整构建矩阵 |

实测编译器版本为 `bcc32` 6.70、`ilink32` 6.51、Delphi Win32 编译器 26.0。BCB 和 Delphi 的目标均为 Windows x86。

安装脚本目前处理清单中的全部 10 个包，下载量共 **138,029,568 字节，约 131.64 MiB**。这 10 个包是本次解码、下载和验证后收录的组件集合，并非整张 ISO 的全部组件。没有 `install` 开关，也不按 BCB/Delphi 分别裁剪清单。

## 2. 先从工程确定需要什么

检查原始工程，而不是仅按“BCB”名称选择编译器：

- `Examples/Code Markers/BCB/Project1.bpr` 标识为 BCB 6 工程，使用 VCL、`WinMain` 和旧式头文件名。
- `Examples/Licensing/BCB/TestApp.cbproj` 记录 `ProjectVersion=15.1`、`FrameworkType=VCL`；源码包含 `System.Classes.hpp`、`Vcl.*`、`_tWinMain` 和 Unicode 字符串。这些是直接可读的工程证据；仅凭这些字段不能证明必须使用 XE5 Update 2。
- BCB 两个工程都需要 VCL 的头文件、库和窗体资源处理工具。只有一个 C++ 编译器 EXE 不足以完成构建。
- Delphi 的两个窗体示例使用 VCL/RTL 和原版 SDK；KeyGen 是使用 RTL 和 `KeyGen32.dll` 的控制台示例。后续迁移还需要匹配版本的 `dcc32.exe` 与 `.dcu`。

早期曾探查 BCB 6 工具链，也实际运行过编译探针。但它不能直接满足 Licensing 的 XE5 头文件及 Unicode VCL 需求，最终没有进入正式 CI。一次早期命令还把二进制 `.res` 交给 C++ 前端处理，产生 `Illegal character` 错误；这属于命令组织错误，后来明确拆开编译与链接步骤。

工程需求限定了需要 Unicode VCL 和命名空间头文件的工具链；搜寻又找到可下载的 XE5 Update 2 介质，最终以实际编译和窗口验证确认兼容。没有进行“最低可用版本”或“只有 Update 2 可用”的比较验证。后续尝试均遵守原始源码、工程、SDK 字节不变的约定：在构建副本中工作，通过外部编译参数和独立中间目录解决兼容问题。

## 3. 找到官方离线介质并读取目录

### 3.1 ISO 链接的搜寻来源

回查当时的搜索与请求记录，发现链接的实际顺序如下：

1. 为寻找包含 VCL 的旧版 C++Builder 工具链，使用同一批搜索词：
   - `"C++Builder XE5" "download" lite`
   - `"C++ Builder 6" "mini" download`
   - `"C++Builder" "Lite" installer github`
2. 搜索结果命中 [Instalacijski mediji（安装介质）](https://embarcadero.konto.hr/instalacijski-mediji/)。结果摘要直接列出了下面的 XE5 Update 2 ISO 完整地址。该页面位于 `embarcadero.konto.hr`，下载文件位于 Embarcadero 的 `altd.embarcadero.com` 域名；两者分别是链接发现来源和文件下载来源。
3. 对摘要中的 ISO 地址发起 HTTP HEAD 请求。2026-09-16 当时的响应为 `HTTP/2 200`，`Content-Length: 5173313536`，并声明 `Accept-Ranges: bytes`。
4. 再单独请求开头 1 MiB，实际收到 `HTTP/2 206` 和 `Content-Range: bytes 0-1048575/5173313536`，确认该次分块读取有效。远程目录读取过程见下一节。

补录本文时重新打开了上述来源页面，确认其 `RAD Studio XE5 with updates` 条目仍明确列出该 ISO 链接，以及在线安装器 `delphi_xe5_upd2_esd.exe` 的链接。这个 ISO 地址直接来自搜索结果；后文组件下载基址的主机名替换是另一项操作。

### 3.2 读取 ISO 目录并定位安装器

采用的官方介质是：[Delphi / C++Builder XE5 Update 2 Windows ISO](https://altd.embarcadero.com/download/radstudio/xe5/delphicbuilder_xe5_upd2_win.iso)。

```text
https://altd.embarcadero.com/download/radstudio/xe5/delphicbuilder_xe5_upd2_win.iso
```

当时确认的 ISO 长度为 **5,173,313,536 字节，约 4.82 GiB**。没有取得整张 ISO 的 SHA-256，不能把 HTTP ETag 当作 ISO 的 SHA-256。

搜寻时先使用 HTTP Range 读取 ISO 的小块数据，以 Python `pycdlib` 解析 Joliet 文件系统目录。临时读取器把远端 ISO 包装为支持 `seek`/`read` 的文件对象，按 1 MiB 对齐请求并缓存数据。本次核查使用 `pycdlib 1.20.0`，仅从已保存的首个 1 MiB 元数据块重新解析，得到相同的安装器与组件位置。

临时远程读取器未进入版本控制。独立复现目录解析时，可先完整下载上面的 ISO，再用下面的本地文件入口；需安装 `pycdlib==1.20.0`，并将 ISO 保存到代码指定的路径。[PyCdlib 的文件打开接口](https://github.com/clalancette/pycdlib/blob/master/docs/example-opening-existing-iso.md) 支持直接读取本地 ISO。

```python
from pathlib import Path
import json
import pycdlib

image = Path('.build/radstudio-xe5-research/delphicbuilder_xe5_upd2_win.iso')
assert image.stat().st_size == 5173313536
iso = pycdlib.PyCdlib()
iso.open(str(image))
for directory, _, files in iso.walk(joliet_path='/'):
    for filename in files:
        path = directory.rstrip('/') + '/' + filename
        record = iso.get_record(joliet_path=path)
        print(path, record.get_data_length())

record = iso.get_record(joliet_path='/Install/Setup.exe')
offset = record.extent_location() * 2048
size = record.get_data_length()
print(offset, size)

manifest = json.loads(Path('ci/radstudio-xe5-toolchain.json').read_text())
for package in manifest['packages']:
    record = iso.get_record(joliet_path='/Install/' + package['name'] + '.7zip')
    assert record.get_data_length() == package['size']
    print(package['name'], record.extent_location() * 2048, record.get_data_length())
iso.close()
```

由目录得到这个版本的外层安装器位置：

| 项目 | 值 |
| --- | --- |
| ISO 内路径 | `/Install/Setup.exe` |
| 起始字节偏移 | `4991617024` |
| 文件长度 | `132840912` |
| Range 末尾字节，包含该字节 | `5124457935` |
| SHA-256 | `300000b70e29b5b180b449331a6a72d2d90999ed2e3d9e9b8895acef67e1fb4b` |

目录还列出 `/Install/bcbwin32.7zip`、`corewin32.7zip`、`transmogrifierc.7zip` 等组件及其精确长度。最初尝试按各组件的 ISO 偏移直接下载，但服务端有时忽略 Range，返回整张 ISO，因而没有将该方法用于正式 CI。

下面是提取这个固定版本安装器的 Range 复现命令。`--max-filesize` 限制响应大小；收到文件后还必须校验摘要：

```bash
research=.build/radstudio-xe5-research
mkdir -p "$research"
curl --fail --location --retry 3 --connect-timeout 30 --max-time 300 \
  --range 4991617024-5124457935 --max-filesize 132840912 \
  --dump-header "$research/setup.headers" \
  --output "$research/Setup.exe" \
  'https://altd.embarcadero.com/download/radstudio/xe5/delphicbuilder_xe5_upd2_win.iso'

python3 - <<'PY'
from pathlib import Path
import hashlib
p = Path('.build/radstudio-xe5-research/Setup.exe')
assert p.stat().st_size == 132840912
assert hashlib.sha256(p.read_bytes()).hexdigest() == (
    '300000b70e29b5b180b449331a6a72d2d90999ed2e3d9e9b8895acef67e1fb4b'
)
print('Outer Setup.exe verified')
PY
```

若 Range 不再可靠，可以下载完整 ISO 后用 7-Zip 提取 `Install/Setup.exe`，再执行同一摘要校验。不要通过截取一个错误响应的前若干字节来假定它是目标文件。

## 4. 解开外层安装器，取得内层安装程序

这里有两个同名 `Setup.exe`，必须分清：

| 层级 | 长度 | SHA-256 |
| --- | --- | --- |
| ISO 中的外层 `Install/Setup.exe` | `132840912` | `300000b70e29b5b180b449331a6a72d2d90999ed2e3d9e9b8895acef67e1fb4b` |
| 外层解出的内层 `Setup.exe` | `16909721` | `c672e244498c73a90dac4b118ec081888989f26d9ed2cb0ab8bf051f9e2df533` |

外层是 InstallAware 自解压安装入口，包含一个未加密的 7z 数据区。其 7z 签名 `37 7A BC AF 27 1C` 位于文件偏移 **170045（`0x2983d`）**。早期手工从该偏移切出 `setup-payload.7z` 后解包；后来核实 7-Zip 可以直接识别外层 EXE 并解出同样的内层文件。

以下命令已用本机 7-Zip 25.01 验证。Windows 通常使用 `7z`，macOS/Linux 的独立发行版可执行文件可能叫 `7zz`：

```bash
7zz l .build/radstudio-xe5-research/Setup.exe
7zz x -y -o.build/radstudio-xe5-research/setup \
  .build/radstudio-xe5-research/Setup.exe Setup.exe
```

外层还包含 `Setup.msi`、`Setup.res`、`OFFLINE/` 等文件。安装脚本、组件表和文件安装表位于**内层 `Setup.exe` 的二进制数据中**，不是一个直接可读的外置 JSON。

本次用 Latin-1 读取内层 EXE，保证每个字节都能一对一映射为字符，然后按 CRLF 分隔数据定位记录。为了辅助检索，还把字符串记录输出到临时 `setup-script.txt`。该文本文件的行号只对应这次导出，不能替代二进制版本和摘要。

## 5. 下载基址从哪里来

在内层安装器里找到相邻的配置项：

```text
UPDATE_STRING
Delphi XE5 and C++Builder XE5 Update 2
...
BASEURL
http://installers.codegear.com/release/radstudio/12.0/DB629168-0140-4C2D-9E68-79614F3D3B4E
```

在已校验 SHA-256 的内层 EXE 中，`UPDATE_STRING` 位于文件偏移 `0xb2b531`，包含 URL 值的 `BASEURL` 位于 `0xb2b620`。前面还存在同名变量声明，不能只取第一次出现的 `BASEURL`。因此，`/release/radstudio/12.0/DB629168-0140-4C2D-9E68-79614F3D3B4E` 这段路径直接来自安装器配置。

当前清单使用的域名则是后续验证结果：保留同一路径，把基址换为 Embarcadero 下载 ISO 所用的官方域名 `https://altd.embarcadero.com`，追加已知组件文件名，实际下载并检查内容。**安装器里记录的是 `installers.codegear.com`，并没有直接写入现在的 `altd.embarcadero.com` 地址。**

```text
https://altd.embarcadero.com/release/radstudio/12.0/DB629168-0140-4C2D-9E68-79614F3D3B4E/<包名>.7zip
```

曾尝试的旧 `installers.codegear.com` 地址返回 403；把域名猜成 `installers.embarcadero.com` 也没有获得可用下载。最终采用的是实际下载成功的 `altd.embarcadero.com`。

## 6. 组件密码怎么获取和解码

内层安装器的组件表中，包名下一行是混淆后的密码。该版本的相关记录可以从二进制偏移 `0x7c0000` 之后搜索；从这个区域开始，是为了避开前面其他同名字符串。

以 `bcbwin32` 为例：

```text
包名记录起点：0x7cc8de
下一行原始字符串：E735=3>2N?;==8<8!'+%
逐字符 XOR 后：   E6169685F61615271696
解码出的密码：    naiXoaQrai
```

恢复过程是：

1. 将混淆字符串第 `i` 个字符的字节值与零起始索引 `i` 做 XOR。
2. 得到十六进制字符序列。
3. 每两个十六进制字符交换顺序，再转换为一个字节。例如 `E6` 交换为 `6E`，即字符 `n`。
4. 将结果按 ASCII 解码，作为对应 `.7zip` 的密码。

算法来源需要区分证据强度：历史工具记录保留了包名附近的原始字符串，以及随后采用上述算法的脚本和成功解包结果；没有保留逐步试验其他变换的记录，也没有安装器解码函数的反汇编证明。这里应表述为**对该版本数据推导并实测成立的解码规则**，不能据此声称它来自厂商规范或适用于所有 InstallAware 版本。此次核查重新按该规则得到清单中的全部 10 个密码，并逐包执行 `7zz t`，全部返回 0。完整解包和校验成功才是密码可用的证据。

为便于从原始文件定位，下面列出全部记录。密码记录偏移指内层 EXE 中 `\r\n<包名>\r\n` 开头的 CR 字节；ISO 偏移指该组件数据起点。

| 组件 | 内层 EXE 密码记录偏移 | ISO 数据偏移 |
| --- | --- | ---: |
| `bcbwin32` | `0x7cc8de` | 1603371008 |
| `corewin32` | `0x7cd5ff` | 2745300992 |
| `core` | `0x7ccddf` | 2022647808 |
| `corewin32xyz` | `0x7cd69a` | 2708842496 |
| `vclwin32runtimes` | `0x7cc76c` | 5164666880 |
| `transmogrifierc` | `0x7cd1d5` | 5163405312 |
| `corecx` | `0x7ccfc9` | 2276237312 |
| `coredelphibcb` | `0x7cd7dc` | 2276552704 |
| `delphiwin32` | `0x7ccb86` | 2894313472 |
| `transmogrifierd` | `0x7cd288` | 5162727424 |

下面的脚本可对当前清单中的全部包重新提取密码，并与清单逐项比较：

```python
from pathlib import Path
import hashlib
import json
import re

installer = Path('.build/radstudio-xe5-research/setup/Setup.exe').read_bytes()
assert hashlib.sha256(installer).hexdigest() == (
    'c672e244498c73a90dac4b118ec081888989f26d9ed2cb0ab8bf051f9e2df533'
)
text = installer.decode('latin1')
manifest = json.loads(Path('ci/radstudio-xe5-toolchain.json').read_text())

for package in manifest['packages']:
    marker = '\r\n' + package['name'] + '\r\n'
    offset = text.find(marker, 0x7c0000)
    if offset < 0:
        raise ValueError(f"Missing package record: {package['name']}")
    encoded = text[offset + len(marker):].split('\r\n', 1)[0]
    hex_text = ''.join(chr(ord(char) ^ i) for i, char in enumerate(encoded))
    if len(hex_text) % 2 or not re.fullmatch(r'[0-9A-Fa-f]+', hex_text):
        raise ValueError(f"Invalid encoded password: {package['name']}")
    password = bytes(
        int(hex_text[i + 1] + hex_text[i], 16)
        for i in range(0, len(hex_text), 2)
    ).decode('ascii')
    assert password == package['password'], package['name']
    print(package['name'], password)
```

## 7. 找包：包名与实际内容不能混为一谈

最终清单如下。每个包的完整 SHA-256 和目录映射保存在版本控制中的 [JSON 清单](../ci/radstudio-xe5-toolchain.json)，安装脚本以该清单为准。

| 组件 | 字节数 | 解压密码 | 相关内容 |
| --- | ---: | --- | --- |
| `bcbwin32` | 31,785,827 | `naiXoaQrai` | C++ 头文件、C/C++ 运行库及 Windows 平台库 |
| `corewin32` | 32,008,305 | `iViajuap!e` | Delphi/VCL/RTL 的 Win32 release DCU、库及公共二进制 |
| `core` | 34,132,673 | `ion!daeCZio` | 公共工具和资源文件 |
| `corewin32xyz` | 35,659,953 | `naq9aevaz1` | Win32 debug DCU 和库 |
| `vclwin32runtimes` | 1,061,039 | `ickousIA5E` | VCL 相关运行时组件和库 |
| `transmogrifierc` | 560,703 | `aeGuckiafg` | 实际 C++ 编译器 `bcc32.exe` |
| `corecx` | 157,487 | `MaejoCSl!2` | 链接器 `ilink32.exe` |
| `coredelphibcb` | 1,735,935 | `ieXiqba8ach` | 资源链接器 `rlink32.dll`、`make.exe` 等公共工具 |
| `delphiwin32` | 337,503 | `ackUczia9ua` | Delphi IDE 集成 BPL，不含 `dcc32.exe` |
| `transmogrifierd` | 590,143 | `cha5ozio7au` | 实际 Delphi 编译器 `DCC32.EXE` |

其中两个容易误判的地方：

- **`bcbwin32` 并不单独包含完整的命令行编译链。** `bcc32.exe` 位于 `transmogrifierc`；`ilink32.exe` 位于 `corecx`；资源链接需要的 `rlink32.dll` 位于 `coredelphibcb`。
- **`delphiwin32` 不含 `dcc32.exe`。** 该包中的 `delphide190.bpl`、`delphicompro190.bpl` 等是 IDE 集成组件。真正的 Delphi 编译器位于 `transmogrifierd`。

另外，外层安装器解出的 `OFFLINE/D00A4462/5B1EB07/dcc32.exe` 只有 **23,040 字节**，里面含有提示：

```text
This version of the product does not support command line compiling.
```

它是占位程序。继续在文件安装表中搜索所有 `DCC32.EXE`，找到：

```text
transmogrifierd\3204ED6B\E8D2221\DCC32.EXE
bin\
```

下载并解开 `transmogrifierd.7zip` 后得到 `transmogrifierd/E8D2221/DCC32.EXE`，大小 **1,558,904 字节**。这个文件在 Windows runner 上实际报告 Delphi Win32 compiler version 26.0，并完成三个项目的编译。

## 8. 从安装器文件表恢复目录结构

组件解包后采用哈希目录名，不能把所有文件平铺到一个目录。安装器的文件表同时记录了包内来源和安装目标，例如：

```text
transmogrifierd\3204ED6B\E8D2221\DCC32.EXE
bin\

coredelphibcb\A8A58556\F311ED39\rlink32.dll
bin\
```

其中 `3204ED6B` / `A8A58556` 是文件表记录中的一层标识；实际组件归档里的路径分别是：

```text
transmogrifierd/E8D2221/DCC32.EXE
coredelphibcb/F311ED39/rlink32.dll
```

这两个来源记录在内层 EXE 中的文件偏移分别是 `0xedaa40` 和 `0xefebe6`，均从包名首字节开始。目录映射的证据来自这些来源/目标相邻记录及归档实际路径；本文没有证明中间标识的生成算法。

因此清单保存的是目录组到目标目录的对应关系：

```json
{"E8D2221": "bin"}
```

按这种方式还恢复出了 `include/windows/vcl`、`include/windows/rtl`、`include/windows/crtl`、`include/windows/sdk`、`include/dinkumware`、`lib/win32/release` 和 `lib/win32/release/psdk` 等目录。

下面的核心解析逻辑可重新检查清单中的每个目录映射。它只读取安装器和 JSON，不修改工具链：

```python
from pathlib import Path, PureWindowsPath
import json
import re

text = Path('.build/radstudio-xe5-research/setup/Setup.exe').read_bytes().decode('latin1')
manifest = json.loads(Path('ci/radstudio-xe5-toolchain.json').read_text())
for package in manifest['packages']:
    pattern = (r'\r\n(' + re.escape(package['name'])
               + r'\\[0-9A-F]+\\[0-9A-F]+\\[^\r\n]+)\r\n([^\r\n]*)\r\n')
    discovered = {}
    for source, target in re.findall(pattern, text):
        target = PureWindowsPath(target)
        if not target.parts or target.parts[0].lower() not in ('bin', 'lib', 'include'):
            continue
        group = PureWindowsPath(source).parts[-2]
        destination = target.as_posix()
        if group in discovered and discovered[group] != destination:
            raise ValueError((package['name'], group, discovered[group], destination))
        discovered[group] = destination
    for group, destination in package['directories'].items():
        assert discovered[group] == destination, (package['name'], group)
    print(package['name'], 'directory mapping verified')
```

同一个组件可能还包含 IDE、设计期或其他平台的目录。清单的 `directories` 是本次实际复制到工具链中的目录子集；包本身始终完整下载和解压。`corewin32xyz` 的 `lib/win32/debug` 后来按要求加入清单，当前构建仍使用 `release` 库。

## 9. 下载、校验、解包和组装

搜寻阶段先从 ISO 目录取得包名和长度，早期按 Range 取得部分组件，随后转为直接组件地址下载。完整拿到文件后计算 SHA-256，把结果固定到清单中。摘要值是对本次取得的原始文件计算得到的，并非声称来自厂商单独发布的签名清单。

本次核查确认 10 个组件的名称和长度均与 ISO 目录一致，密码均从同一内层安装器解出，归档均通过完整性测试。但未对全部 10 个直链下载包与 ISO 对应区间逐字节比较。`bcbwin32.7zip` 与单独下载的 `bcbwin32-direct.7zip` 内容一致；`coredelphibcb.7zip` 则是在 Range 失败后从 `coredelphibcb-direct.7zip` 复制而来，这两个文件相同不能算独立交叉验证。

单个组件的复现示例：

```bash
research=.build/radstudio-xe5-research
base='https://altd.embarcadero.com/release/radstudio/12.0/DB629168-0140-4C2D-9E68-79614F3D3B4E'
curl --fail --location --retry 3 --connect-timeout 30 --max-time 300 \
  --max-filesize 590143 --output "$research/transmogrifierd.7zip" \
  "$base/transmogrifierd.7zip"

python3 - <<'PY'
from pathlib import Path
import hashlib
import json
manifest = json.loads(Path('ci/radstudio-xe5-toolchain.json').read_text())
package = next(p for p in manifest['packages'] if p['name'] == 'transmogrifierd')
archive = Path('.build/radstudio-xe5-research/transmogrifierd.7zip')
assert archive.stat().st_size == package['size']
assert hashlib.sha256(archive.read_bytes()).hexdigest() == package['sha256']
PY

7zz t -pcha5ozio7au "$research/transmogrifierd.7zip"
7zz x -y -pcha5ozio7au "-o$research/packages" "$research/transmogrifierd.7zip"
```

早期尝试过 Python `py7zr`，没有完成这些旧组件包的解包；最终使用实际验证成功的 7-Zip。组件包使用 7z 加密，解包密码通过上面的安装器数据解码得到。正式 CI 没有引入 Python 解压依赖。

当前 PowerShell 安装脚本执行以下流程：

1. 若 `.build/radstudio-xe5` 已存在则停止，避免覆盖已有工具链。
2. 遍历 JSON 的全部 `packages`。
3. 下载缺失的 `.7zip` 到 `.build/downloads/radstudio-xe5`。
4. 无论新下载还是缓存恢复，都检查精确文件长度和 SHA-256。
5. 使用 `7z x -p...` 解到 `.build/radstudio-xe5-unpack`。
6. 按 `directories` 把各目录组复制到 `.build/radstudio-xe5`。
7. 检查编译器、链接器、资源工具、头文件和 RTL/VCL 库是否存在。

下载包、解包目录和最终工具链三个目录分别保留，便于定位失败。CI 缓存的是原始组件包；缓存键包含清单和安装脚本摘要。两个构建任务使用相同的缓存键和安装脚本，但每个 runner 分别组装自己的工具链。

研究阶段解开外层安装器是为了读取元数据。正式 CI 从 4.82 GiB 安装介质对应的组件集合中准备命令行工具，不运行完整 IDE 安装，也没有修改编译器二进制。小体积 `.7zip` 是组件数据归档，本身不是可执行的完整安装器。

## 10. 组装后遇到的问题与修正

| 现象或错误 | 定位结果和处理 |
| --- | --- |
| ISO Range 有时取得超大响应 | 不把 HTTP 成功视为切片成功；检查长度，正式 CI 改用独立组件 URL |
| 旧下载域名不可用，目录地址 404 | 从安装器确定路径，再针对具体文件验证 `altd.embarcadero.com`；不依赖目录浏览 |
| BCB 6 探针把 `.res` 当 C++ 输入，报 `Illegal character` | C++ 源文件单独编译，原 `.res` 只交给链接器 |
| `Error: Unable to open file 'UNIT1.DFM'` | OBJ 内记录的是相对资源名，将原 DFM 复制到独立 OBJ 目录供链接器读取 |
| `Error: Could not load RLINK32.DLL` | `ilink32.exe` 存在不代表资源链接依赖齐全；补入 `coredelphibcb` 中的 `rlink32.dll` |
| `Unable to open include file 'VMProtectSDK.h'` | Licensing 没有本地头文件链接，追加真正的 `Include/C` 搜索路径 |
| 原 SDK 导入库是 COFF，BCB 链接需要 OMF | 用官方 `implib.exe` 从原 DLL 生成 OMF 到中间目录，优先从该目录解析；原 `.lib` 不变 |
| 没有得到需要的 MAP | `-x` 是禁用 MAP，`-GD` 是生成 DRC；采用 `ilink32 -s` 生成详细 MAP |
| BCB Licensing 启动报 `Abnormal program termination` | 将 C/C++ RTL 从 `cw32mt.lib` 改为原 BCB 工程也使用的 `cp32mt.lib`，两个窗体启动和退出均通过 |
| `Process.MainWindowTitle` 看到 `Project1`，与窗体标题不符 | VCL 还有辅助窗口；按本轮 PID 枚举窗口，要求可见 `TForm1` 且标题匹配原 DFM |
| `OFFLINE/.../dcc32.exe` 提示不支持命令行编译 | 它是 23,040 字节占位程序；使用 `transmogrifierd` 的真实编译器 |
| Delphi 旧源码使用 `Forms`、`Windows`、`SysUtils` | 用 `-NSSystem;Winapi;Vcl` 解析单元名，并指定 XE5 `lib/win32/release` |

### BCB 最终构建方式

直接编译原始 `.cpp`，不升级 `.bpr` / `.cbproj`。Code Markers 使用 `c0w32.obj`；Licensing 使用 `c0w32w.obj` 并定义 `_UNICODE` / `UNICODE`。链接原 `.res`，保留图标、版本和应用 manifest。

VCL 和 C/C++ RTL 静态链接。输出为 EXE、详细 MAP、TDS 和原 `VMProtectSDK32.dll`。生成的 OMF 导入库、OBJ、DFM 副本和链接响应文件留在中间目录，不进入示例 ZIP。

### Delphi 最终构建方式

直接调用 XE5 `dcc32.exe` 编译原 `.dpr`，使用匹配的 RTL/VCL，设置 `-NSSystem;Winapi;Vcl`、`-N0` 中间目录、`-E` 输出目录及 `-GD` 详细 MAP。

Licensing 的原 `.dpr` 引用一个缺失的 `TestApp.res`，延续已有做法：仅在构建副本生成空资源。原始 `.dpr`、`.pas`、DFM、工程和旧 `TestApp.map` 均不变。

XE5 会对原始源码报告三处 `W1057` 隐式字符串转换警告，以及 Code Markers 中的内联提示。日志保留这些诊断；不把成功构建描述为“没有警告”。

KeyGen 调用示例携带原 `KeyGen32.dll`。由于原始产品参数为空，运行结果应为 `Error: 2`，脚本精确检查这个输出和零退出码。这不是实际签发序列号的验收。

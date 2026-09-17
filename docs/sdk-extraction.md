# SDK 提取与校验

本文说明原始文件的保留规则，以及从原始 ZIP 重新提取 SDK 的方法。

## 文件来源与处理规则

从 `VMProtectSDK-3.5.0.1249.zip` 提取的 SDK 与示例。清单使用 `version` 字段记录版本号 `3.5.0.1249`。

- 原始 ZIP SHA-256：`4b55d8c61ab7f3f5fb8bb75f32fb1eb35f8dd6441dcf0d9337357322e7f3beb9`。
- `Include/`、`Lib/` 以及保留的示例源码、工程、资源和 `makeit.*` 均保留原始字节。
- 移除 Examples 内的 21 个预编译程序（含示例驱动）和 1 个程序别名。保留 `Examples/Scripts/` 下全部 5 个 executable，以及 `.vmp`、`.map`、`.res`、应用资源与依赖库。
- 48 个重复 SDK 文件改为指向 `Include/` 或 `Lib/` 的相对符号链接。增加 2 个 GCC Linux SDK 链接，使原始 `makeit.sh` 能找到库。
- 替换链接前逐字节匹配原件。因此 BCB 目录中原有的 COFF import library 仍指向相同的 COFF 文件，不擅自换成 OMF。

原始 SDK 和示例的版权及许可归各自权利人所有。此仓库未为这些文件另行授予开源许可。

## 重放提取

在仓库根目录执行以下命令。提取脚本见 [`extract.py`](../extract.py)。

需要 Python 3 以及支持符号链接的文件系统。将 `extract.py` 放入新目录：

```bash
mkdir vmpsdk-extracted
cp extract.py vmpsdk-extracted/
python3 vmpsdk-extracted/extract.py /path/to/VMProtectSDK-3.5.0.1249.zip --version 3.5.0.1249
```

版本号必须通过 `--version` 手动指定，格式为 `X.X.X.X`。脚本不从 ZIP 文件名推断版本。

内容写入脚本所在目录，不依赖调用时的工作目录。若 `Examples/`、`Include/`、`Lib/` 或清单已存在，脚本拒绝覆盖。
脚本校验 ZIP CRC、拒绝越界路径，记录原包摘要、保留文件摘要、链接及删除原因到 [`extraction-manifest.json`](../extraction-manifest.json)。

## 克隆与校验

克隆时保留实际符号链接：

```bash
git -c core.symlinks=true clone https://github.com/LanceaKing/vmpsdk.git
cd vmpsdk
python3 ci/verify.py
```

Windows 需要允许创建符号链接（开发者模式或管理员权限）。GitHub Windows runner 在 checkout 前配置 `core.symlinks=true`。
仅下载 GitHub 源码 ZIP 不会替你创建这些链接。

校验脚本 [`ci/verify.py`](../ci/verify.py) 按清单检查导入文件及符号链接。
构建副本的校验方法见 [构建与验证](building.md)。

# 版本发布

[Release 工作流](../.github/workflows/release.yml) 构建 SDK 和全部示例，然后创建 GitHub draft release。
版本号以 [`extraction-manifest.json`](../extraction-manifest.json) 的 `version` 字段为准。

## 创建草稿

在 GitHub Actions 中打开 **Release**，选择 **Run workflow** 并运行。
工作流直接读取提取清单中的版本号，无需填写版本参数。
也可以在仓库根目录执行：

```bash
gh workflow run release.yml --ref main
```

推送 `3.5.0.1249` 这样的四段数字 tag 也会触发同一流程。
tag 必须与提取清单中的 `version` 一致。
工作流只创建草稿。确认附件和说明后，在 GitHub Release 页面手动发布。

## 发布附件

- `vmpsdk-<版本号>.zip`：包含 `Include/`、`Lib/`、`Examples/` 和提取清单。
- 每个示例项目的 ZIP：名称和内容遵守 [构建产物约定](build-artifacts.md)。
- `SHA256SUMS`：包含全部 ZIP 的 SHA-256。

SDK ZIP 按提取清单逐文件校验，并将符号链接展开为原始文件内容。文件权限保留，普通解压工具无需创建符号链接。
Scripts 配套程序和 PHP 示例包含在 SDK ZIP 中。

示例 ZIP 来自本次工作流调用的 [Build examples](../.github/workflows/build.yml)。下载与上传均保留 ZIP 原始字节，不重新打包。
所有构建必须成功，附件名称必须覆盖 [`ci/package.py`](../ci/package.py) 中的全部项目。
发布前还会检查 ZIP 完整性、根目录布局、运行依赖和 Unix 执行权限。

工作流将草稿绑定到本次构建的提交，并核对每个上传附件的大小和 SHA-256。
重跑可以更新同一提交的草稿。已正式发布的版本、指向其他提交的草稿或同名 tag 均不会被覆盖。

## 本地打包 SDK

```bash
python3 ci/verify.py
python3 ci/package.py sdk
```

输出为 `.build/archives/vmpsdk-<version>.zip`，版本号读取自提取清单。已有 ZIP 不会被覆盖。

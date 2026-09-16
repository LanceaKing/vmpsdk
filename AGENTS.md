# 构建产物约定

修改构建、打包或上传步骤时，遵守以下约定：

- 每个项目生成独立 ZIP。文件名为 `<平台>-<架构>-<工具链>-<项目>.zip`，全部使用小写字母、数字和连字符，例如 `windows-x86-masm-markers.zip`。
- 平台表示产物的目标系统，使用 `windows`、`linux` 或 `macos`。Linux 上交叉编译的 MinGW 产物仍使用 `windows`。
- 架构按实际产物填写：`x86`、`x64` 或 `any`。保留原 .NET 工程的 AnyCPU 配置。
- 项目文件直接位于 ZIP 根目录。macOS 的 `.app` 和 `.dSYM` 放在根目录，并保留包内结构。
- 每个 ZIP 包含一个项目的输出及运行依赖。KeyGen 库和调用示例分别打包，调用示例携带所需的 KeyGen 库。
- 保留运行配置、manifest、映射文件、调试符号及库项目的导入库。排除中间文件、安装包、构建日志和其他项目的输出。
- ZIP 保留 Unix 文件权限和符号链接。使用 `actions/upload-artifact` 的 `archive: false` 上传已生成的 ZIP，下载文件即为该 ZIP。
- 在 `ci/package.py` 中维护产物名称和文件清单，通过 `.github/actions/package-project` 打包、验证并上传。

完成修改前，运行打包测试和 workflow 检查。实际构建后，核对每个下载 ZIP 的名称、根目录内容、运行依赖及 Unix 执行权限。

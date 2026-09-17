#!/usr/bin/env python3
"""Prepare complete release assets and create a draft from one successful build."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import stat
import subprocess
import zipfile

from package import PROJECTS, package_sdk, sdk_version


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def example_names() -> set[str]:
    return {f'{name}.zip' for name in PROJECTS}


def require_files(directory: Path, expected: set[str]) -> None:
    actual = {path.name for path in directory.iterdir()}
    if actual != expected:
        raise ValueError(f'Release assets differ: missing={sorted(expected - actual)}, extra={sorted(actual - expected)}')
    for name in expected:
        path = directory / name
        if not path.is_file() or path.is_symlink() or path.stat().st_size == 0:
            raise ValueError(f'Missing or empty release asset: {name}')


def verify_examples(assets: Path) -> None:
    for name, project in PROJECTS.items():
        with zipfile.ZipFile(assets / f'{name}.zip') as archive:
            names = archive.namelist()
            if len(names) != len(set(names)) or archive.testzip() is not None:
                raise ValueError(f'Invalid example ZIP: {name}')
            allowed = set(project.required + project.optional)
            for member in names:
                path = PurePosixPath(member)
                if (not path.parts or path.is_absolute() or '..' in path.parts or '\\' in member
                        or path.parts[0] not in allowed
                        or (len(path.parts) > 1 and not path.parts[0].endswith(('.app', '.dSYM')))):
                    raise ValueError(f'Unexpected example member: {name}: {member}')
            for required in project.required:
                files = [info for info in archive.infolist() if not info.is_dir()
                         and (info.filename == required or info.filename.startswith(required + '/'))]
                if not files or not any(info.file_size for info in files):
                    raise ValueError(f'Missing or empty example output: {name}: {required}')
            if name.startswith(('linux-', 'macos-')):
                executable = project.required[0]
                if executable.endswith('.app'):
                    plist = plistlib.loads(archive.read(f'{executable}/Contents/Info.plist'))
                    executable = f'{executable}/Contents/MacOS/{plist["CFBundleExecutable"]}'
                mode = archive.getinfo(executable).external_attr >> 16
                if not stat.S_ISREG(mode) or not mode & 0o111:
                    raise ValueError(f'Unix executable permission missing: {name}: {executable}')


def checksums(assets: Path, names: set[str]) -> str:
    return ''.join(f'{sha256(assets / name)}  {name}\n' for name in sorted(names))


def prepare(root: Path, assets: Path) -> None:
    version = sdk_version(root)
    names = example_names()
    require_files(assets, names)
    verify_examples(assets)
    sdk = package_sdk(root, assets)
    names.add(sdk.name)
    with (assets / 'SHA256SUMS').open('x') as stream:
        stream.write(checksums(assets, names))
    notes = (
        f'VMProtect SDK {version} 的接口、库、示例源码和编译好的示例。\n\n'
        f'- `{sdk.name}`：包含 `Include/`、`Lib/`、`Examples/` 和原始文件校验清单。'
        'SDK 符号链接已展开为实际文件，解压无需创建符号链接。\n'
        f'- 其余 {len(PROJECTS)} 个 ZIP：Windows、Linux 和 macOS 的全部 CI 示例产物，'
        '每个包包含一个项目的输出及所需 SDK 或 KeyGen 库。\n'
        '- `SHA256SUMS`：所有 ZIP 的 SHA-256 校验值。\n\n'
        '按 ZIP 文件名选择平台、架构和工具链。macOS 示例面向 Intel x64，不含 ARM64 库。'
        'Scripts 配套程序和 PHP 示例包含在 SDK ZIP 中。\n\n'
        '这些产物是未经 VMProtect 保护的示例。KeyGen 示例使用空产品参数，'
        'DDK 驱动未签名、未加载测试。\n\n'
        '此 SDK ZIP 是仓库整理版，文件内容按原始提取清单校验。'
        '原始 SDK 和示例的版权及许可归各自权利人所有。\n'
    )
    if os.environ.get('GITHUB_RUN_ID'):
        notes += (f'\n构建记录：https://github.com/{os.environ["GITHUB_REPOSITORY"]}'
                  f'/actions/runs/{os.environ["GITHUB_RUN_ID"]}\n')
    (assets.parent / 'notes.md').write_text(notes, encoding='utf-8')
    print(f'PASS: {len(names)} ZIPs and SHA256SUMS ready for a draft release')


def check_draft(release: dict, commit: str, names: set[str]) -> None:
    if not release['draft']:
        raise ValueError('Refusing to modify a published release')
    if release['target_commitish'] != commit:
        raise ValueError('Existing draft targets another commit')
    extra = {asset['name'] for asset in release['assets']} - names
    if extra:
        raise ValueError(f'Existing draft contains unexpected assets: {sorted(extra)}')


def verify_uploaded(release: dict, commit: str, assets: Path, names: set[str]) -> None:
    check_draft(release, commit, names)
    uploaded = {asset['name']: asset for asset in release['assets']}
    if set(uploaded) != names:
        raise ValueError(f'Draft assets incomplete: {sorted(names - set(uploaded))}')
    for name, asset in uploaded.items():
        path = assets / name
        if (asset['state'] != 'uploaded' or asset['size'] != path.stat().st_size
                or asset.get('digest') != f'sha256:{sha256(path)}'):
            raise ValueError(f'Draft asset differs from local file: {name}')


def gh_json(*arguments: str):
    return json.loads(subprocess.check_output(['gh', *arguments], text=True))


def draft(root: Path, assets: Path) -> None:
    version = sdk_version(root)
    names = example_names() | {f'vmpsdk-{version}.zip'}
    require_files(assets, names | {'SHA256SUMS'})
    if (assets / 'SHA256SUMS').read_text() != checksums(assets, names):
        raise ValueError('Release checksum file does not match assets')
    names.add('SHA256SUMS')
    repo = os.environ['GITHUB_REPOSITORY']
    commit = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    if commit != os.environ['GITHUB_SHA']:
        raise ValueError('Checkout does not match the release workflow commit')
    tag = subprocess.run(['git', '-C', str(root), 'rev-parse', '-q', '--verify',
                          f'refs/tags/{version}^{{commit}}'], capture_output=True, text=True)
    if tag.returncode not in (0, 1) or (tag.returncode == 0 and tag.stdout.strip() != commit):
        raise ValueError('Existing version tag does not match the release commit')
    pages = gh_json('api', f'repos/{repo}/releases?per_page=100', '--paginate', '--slurp')
    existing = next((release for page in pages for release in page if release['tag_name'] == version), None)
    options = ['--repo', repo, '--draft', '--target', commit, '--title', version,
               '--notes-file', str(assets.parent / 'notes.md')]
    paths = [str(assets / name) for name in sorted(names)]
    if existing:
        check_draft(existing, commit, names)
        subprocess.run(['gh', 'release', 'edit', version, *options], check=True)
        subprocess.run(['gh', 'release', 'upload', version, '--repo', repo, '--clobber', *paths], check=True)
    else:
        subprocess.run(['gh', 'release', 'create', version, *options, *paths], check=True)
    release_id = gh_json('release', 'view', version, '--repo', repo, '--json', 'databaseId')['databaseId']
    release = gh_json('api', f'repos/{repo}/releases/{release_id}')
    verify_uploaded(release, commit, assets, names)
    print(f'PASS: draft {release["html_url"]}: {len(names)} verified assets')
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with Path(os.environ['GITHUB_STEP_SUMMARY']).open('a') as summary:
            summary.write(f'[{version} draft release]({release["html_url"]})\n\n'
                          f'{len(names)} assets verified by SHA-256.\n')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['validate', 'prepare', 'draft'])
    parser.add_argument('--assets', type=Path, default=Path('.build/release/assets'))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.command == 'validate':
        version = sdk_version(root)
        if os.environ.get('GITHUB_REF_TYPE') == 'tag' and os.environ.get('GITHUB_REF_NAME') != version:
            raise ValueError(f'Release tag does not match SDK version {version}')
        print(f'PASS: release version {version} from extraction-manifest.json')
    elif args.command == 'prepare':
        prepare(root, args.assets)
    else:
        draft(root, args.assets)


if __name__ == '__main__':
    main()

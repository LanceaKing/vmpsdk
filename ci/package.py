#!/usr/bin/env python3
"""Package one example and its dependencies at the root of a ZIP file."""
import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import zipfile


@dataclass(frozen=True)
class Project:
    folder: str
    required: tuple[str, ...]
    optional: tuple[str, ...] = ()


PROJECTS = {
    'windows-x86-ddk-licensing': Project(
        'licensing-ddk-x86', ('TestApp.sys', 'VMProtectDDK32.sys', 'TestApp.map', 'TestApp.pdb')),
    'windows-x86-mingw-markers': Project(
        'mingw-x86', ('Project1.exe', 'VMProtectSDK32.dll'), ('Project1.map',)),
    'windows-x86-masm-markers': Project(
        'masm-x86', ('Project1.exe', 'VMProtectSDK32.dll')),
    'windows-x86-vb6-markers': Project(
        'markers-vb6-x86', ('Project1.exe', 'VMProtectSDK32.dll')),
    'windows-x86-vb6-licensing': Project(
        'licensing-vb6-x86', ('TestApp.exe', 'VMProtectSDK32.dll')),
    'windows-x86-bcb-markers': Project(
        'markers-bcb-x86', ('Project1.exe', 'VMProtectSDK32.dll', 'Project1.map'),
        ('Project1.tds', 'Project1.exe.manifest')),
    'windows-x86-bcb-licensing': Project(
        'licensing-bcb-x86', ('TestApp.exe', 'VMProtectSDK32.dll', 'TestApp.map'),
        ('TestApp.tds', 'TestApp.exe.manifest')),
    'windows-x86-delphi-markers': Project(
        'markers-delphi-x86', ('Project1.exe', 'VMProtectSDK32.dll', 'Project1.map'),
        ('Project1.tds', 'Project1.exe.manifest')),
    'windows-x86-delphi-licensing': Project(
        'licensing-delphi-x86', ('TestApp.exe', 'VMProtectSDK32.dll', 'TestApp.map'),
        ('TestApp.tds', 'TestApp.exe.manifest')),
    'windows-x86-delphi-keygen-usage': Project(
        'keygen-usage-delphi-x86', ('KeyGenExample.exe', 'KeyGen32.dll', 'KeyGenExample.map'),
        ('KeyGenExample.tds', 'KeyGenExample.exe.manifest')),
    'windows-x86-fpc-markers': Project(
        'fpc-x86', ('Project1.exe', 'VMProtectSDK32.dll')),
    'windows-x86-lazarus-markers': Project(
        'lazarus-x86', ('project1.exe', 'VMProtectSDK32.dll')),
    'windows-any-net-markers': Project(
        'markers-net', ('Project1.exe', 'VMProtect.SDK.dll'),
        ('Project1.pdb', 'Project1.exe.config')),
    'windows-any-net-licensing': Project(
        'licensing-net', ('TestApp.exe', 'VMProtect.SDK.dll'),
        ('TestApp.pdb', 'TestApp.exe.config')),
    'windows-any-net-keygen': Project(
        'keygen-net', ('VMProtect.KeyGen.dll',),
        ('VMProtect.KeyGen.pdb', 'VMProtect.KeyGen.dll.config')),
    'windows-any-net-keygen-usage': Project(
        'keygen-net', ('Usage.exe', 'VMProtect.KeyGen.dll'),
        ('Usage.pdb', 'Usage.exe.config', 'VMProtect.KeyGen.pdb', 'VMProtect.KeyGen.dll.config')),
    'macos-x64-gcc-markers': Project(
        'gcc-x64', ('Project1', 'libVMProtectSDK.dylib')),
    'macos-x64-fpc-markers': Project(
        'fpc-x64', ('Project1', 'libVMProtectSDK.dylib')),
    'macos-x64-xcode-markers': Project(
        '.', ('Project1.app',), ('Project1.app.dSYM',)),
    'macos-x64-xcode-licensing': Project(
        '.', ('VMProtect Licensing Test.app',), ('VMProtect Licensing Test.app.dSYM',)),
}
for arch, bits in (('x86', '32'), ('x64', '64')):
    PROJECTS[f'linux-{arch}-gcc-markers'] = Project(
        f'linux-{arch}', (f'Project1-linux-{arch}', f'libVMProtectSDK{bits}.so'))
    for project, executable in (('markers', 'Project1'), ('licensing', 'TestApp')):
        PROJECTS[f'windows-{arch}-msvc-{project}'] = Project(
            f'{project}-{arch}', (f'{executable}.exe', f'VMProtectSDK{bits}.dll'),
            (f'{executable}.pdb', f'{executable}.map', f'{executable}.exe.manifest'))
    PROJECTS[f'windows-{arch}-msvc-keygen'] = Project(
        f'keygen-{arch}', (f'KeyGen{bits}.dll', f'KeyGen{bits}.lib'), (f'KeyGen{bits}.pdb',))
    PROJECTS[f'windows-{arch}-msvc-keygen-usage'] = Project(
        f'keygen-{arch}', ('KeyGenExample.exe', f'KeyGen{bits}.dll'), ('KeyGenExample.pdb',))


def package(name: str, artifacts: Path, archives: Path) -> Path:
    project = PROJECTS[name]
    source = artifacts / project.folder
    for member in project.required:
        path = source / member
        if not path.exists() or (path.is_file() and path.stat().st_size == 0):
            raise ValueError(f'Missing or empty build output: {path}')

    paths = []
    for member in project.required + project.optional:
        path = source / member
        if path.exists() or path.is_symlink():
            paths.append(path)
            if path.is_dir() and not path.is_symlink():
                paths.extend(sorted(path.rglob('*')))
    if not any(path.is_file() for path in paths):
        raise ValueError(f'No build output files for {name}')

    archives.mkdir(parents=True, exist_ok=True)
    output = archives / f'{name}.zip'
    # Exclusive creation rejects stale output. ZipFile.write preserves Unix modes.
    with zipfile.ZipFile(output, 'x', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in paths:
            member = path.relative_to(source).as_posix()
            if path.is_symlink():
                info = zipfile.ZipInfo(member)
                info.create_system = 3
                info.external_attr = path.lstat().st_mode << 16
                archive.writestr(info, os.readlink(path))
            elif path.is_file() or path.is_dir():
                archive.write(path, member)
            else:
                raise ValueError(f'Unsupported build output: {path}')

    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise ValueError(f'ZIP CRC check failed: {output}')
        for info in archive.infolist():
            original = source / info.filename
            if os.name != 'nt' and stat.S_IMODE(info.external_attr >> 16) != stat.S_IMODE(original.lstat().st_mode):
                raise ValueError(f'ZIP permissions changed: {info.filename}')
        print(f'PASS: {output.name}: {len(archive.infolist())} entries, project files at ZIP root')
    return output


def sdk_version(root: Path) -> str:
    manifest = json.loads((root / 'extraction-manifest.json').read_text())
    version = manifest.get('version')
    if not isinstance(version, str) or not re.fullmatch(r'\d+\.\d+\.\d+\.\d+', version):
        raise ValueError(f'Invalid SDK version in extraction manifest: {version!r}')
    return version


def package_sdk(root: Path, archives: Path) -> Path:
    version = sdk_version(root)
    manifest_path = root / 'extraction-manifest.json'
    manifest = json.loads(manifest_path.read_text())
    files = {}
    for name, record in sorted(manifest['files'].items()):
        member = PurePosixPath(name)
        if (not member.parts or member.is_absolute() or '..' in member.parts or '\\' in name
                or member.parts[0] not in ('Include', 'Lib', 'Examples')):
            raise ValueError(f'Invalid SDK path: {name}')
        path = root / name
        if not path.resolve().is_relative_to(root.resolve()):
            raise ValueError(f'SDK link leaves the repository: {name}')
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != record['sha256']:
            raise ValueError(f'Changed original SDK bytes: {name}')
        files[name] = (data, stat.S_IMODE(path.stat().st_mode))
    files['extraction-manifest.json'] = (manifest_path.read_bytes(), 0o644)
    archives.mkdir(parents=True, exist_ok=True)
    output = archives / f'vmpsdk-{version}.zip'
    with zipfile.ZipFile(output, 'x', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name, (data, mode) in files.items():
            # Expand SDK links for ordinary ZIP extractors. Keep file bytes and modes.
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise ValueError(f'ZIP CRC check failed: {output}')
        for name, (data, mode) in files.items():
            if archive.read(name) != data or stat.S_IMODE(archive.getinfo(name).external_attr >> 16) != mode:
                raise ValueError(f'SDK archive content changed: {name}')
    print(f'PASS: {output.name}: {len(files)} entries, SDK links materialized')
    return output


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('name', choices=sorted(PROJECTS) + ['sdk'])
    args = parser.parse_args()
    if args.name == 'sdk':
        package_sdk(root, root / '.build/archives')
    else:
        package(args.name, root / '.build/artifacts', root / '.build/archives')


if __name__ == '__main__':
    main()

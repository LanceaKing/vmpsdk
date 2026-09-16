#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import struct
import sys
import tempfile
import zipfile

parser = argparse.ArgumentParser(description='Extract VMProtect SDK beside this script without overwriting existing files.')
parser.add_argument('zip', type=Path, help='SDK ZIP with Examples, Include, and Lib at its root')
args = parser.parse_args()
archive, root = args.zip.resolve(), Path(__file__).resolve().parent
roots = ('Examples', 'Include', 'Lib')
for name in (*roots, 'extraction-manifest.json'):
    if os.path.lexists(root / name):
        sys.exit(f'Refusing to overwrite {root / name}; use a fresh directory.')

def sha(data):
    return hashlib.sha256(data).hexdigest()

def macho_executable(data):
    magic = data[:4]
    if magic in (b'\xce\xfa\xed\xfe', b'\xcf\xfa\xed\xfe'):
        return len(data) >= 16 and struct.unpack_from('<I', data, 12)[0] == 2
    if magic in (b'\xfe\xed\xfa\xce', b'\xfe\xed\xfa\xcf'):
        return len(data) >= 16 and struct.unpack_from('>I', data, 12)[0] == 2
    if magic in (b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'):
        endian = '>' if magic == b'\xca\xfe\xba\xbe' else '<'
        count = struct.unpack_from(endian + 'I', data, 4)[0]
        for i in range(count):
            offset, size = struct.unpack_from(endian + 'II', data, 8 + i * 20 + 8)
            if macho_executable(data[offset:offset + size]):
                return True
    return False

def executable_reason(name, data):
    if not name.startswith('Examples/'):
        return None
    # Script demonstrations ship executables without the corresponding sources.
    if name.startswith('Examples/Scripts/'):
        return None
    if name.lower().endswith(('.exe', '.sys')):
        return 'compiled Windows executable or example driver'
    if macho_executable(data):
        return 'compiled Mach-O executable'
    if data[:4] == b'\x7fELF':
        endian = '<' if data[5] == 1 else '>'
        if struct.unpack_from(endian + 'H', data, 16)[0] == 2:
            return 'compiled ELF executable'
    if '.app/Contents/MacOS/' in name and data.startswith(b'XSym\r\n'):
        return 'packaged alias to a removed executable'
    return None

with zipfile.ZipFile(archive) as z, tempfile.TemporaryDirectory(prefix='.extract-', dir=root) as tmp:
    bad = z.testzip()
    if bad:
        sys.exit(f'ZIP CRC check failed: {bad}')
    files = {}
    for info in z.infolist():
        p = PurePosixPath(info.filename)
        if p.is_absolute() or '..' in p.parts or '\\' in info.filename or not p.parts or p.parts[0] not in roots:
            sys.exit(f'Unexpected ZIP path: {info.filename}')
        mode = info.external_attr >> 16
        if stat.S_ISLNK(mode):
            sys.exit(f'Unexpected archive symlink: {info.filename}')
        if not info.is_dir():
            if info.filename in files:
                sys.exit(f'Duplicate ZIP entry: {info.filename}')
            files[info.filename] = z.read(info)
    if any(not any(n.startswith(r + '/') for n in files) for r in roots):
        sys.exit('Expected Examples/, Include/, and Lib/ in the ZIP root.')
    canonical = {n: b for n, b in files.items() if n.startswith(('Include/', 'Lib/'))}
    records, removed = {}, {}
    stage = Path(tmp)
    for name, data in sorted(files.items()):
        reason = executable_reason(name, data)
        if reason:
            removed[name] = {'sha256': sha(data), 'reason': reason}
            continue
        target = None
        base = PurePosixPath(name).name
        if name.startswith('Examples/') and base.startswith(('VMProtectSDK', 'VMProtectDDK', 'libVMProtectSDK', 'VMProtect.SDK')):
            matches = [n for n, b in canonical.items() if PurePosixPath(n).name == base and b == data]
            if len(matches) != 1:
                sys.exit(f'Expected one byte-identical canonical SDK file for {name}: {matches}')
            target = matches[0]
        out = stage / name
        out.parent.mkdir(parents=True, exist_ok=True)
        record = {'sha256': sha(data)}
        if target:
            link = os.path.relpath(stage / target, out.parent).replace(os.sep, '/')
            out.symlink_to(link)
            record['link'] = link
        else:
            out.write_bytes(data)
            out.chmod(0o644)
        records[name] = record
    # The upstream Linux makeit.sh expects these beside Project1.cpp.
    for bits in (32, 64):
        name = f'Examples/Code Markers/GCC/libVMProtectSDK{bits}.so'
        target = f'Lib/Linux/libVMProtectSDK{bits}.so'
        if name not in records:
            out = stage / name
            link = os.path.relpath(stage / target, out.parent).replace(os.sep, '/')
            out.symlink_to(link)
            records[name] = {'sha256': sha(canonical[target]), 'link': link, 'added': True}
    # Verify links resolve to the original bytes before publishing the tree.
    for name, record in records.items():
        if sha((stage / name).read_bytes()) != record['sha256']:
            sys.exit(f'Extracted content mismatch: {name}')
    manifest = {
        'archive': archive.name,
        'archive_sha256': sha(archive.read_bytes()),
        'files': dict(sorted(records.items())),
        'removed': removed,
    }
    (stage / 'extraction-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    for name in (*roots, 'extraction-manifest.json'):
        shutil.move(str(stage / name), root / name)
    print(f'Extracted {len(records)} files; {sum("link" in r for r in records.values())} SDK links; removed {len(removed)} executables/aliases.')
    print(f'Archive SHA-256: {manifest["archive_sha256"]}')

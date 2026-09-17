"""Check SDK contents, release completeness and draft-only updates."""
from contextlib import redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest
import zipfile

from package import PROJECTS, package_sdk, sdk_version
from release import check_draft, checksums, example_names, prepare, verify_uploaded


VERSION = '3.5.0.1249'
REPO = Path(__file__).resolve().parents[1]


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.assets = self.root / 'release/assets'
        self.assets.mkdir(parents=True)
        files = {}
        for name, content in {
            'Include/C/VMProtectSDK.h': b'original header',
            'Lib/Windows/VMProtectSDK32.dll': b'original SDK',
            'Examples/Scripts/Project1.exe': b'shipped script program',
        }.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
            path.chmod(0o755 if name.endswith('.exe') else 0o644)
            files[name] = {'sha256': hashlib.sha256(content).hexdigest()}
        link = self.root / 'Examples/Scripts/VMProtectSDK32.dll'
        link.symlink_to('../../Lib/Windows/VMProtectSDK32.dll')
        files['Examples/Scripts/VMProtectSDK32.dll'] = {
            **files['Lib/Windows/VMProtectSDK32.dll'], 'link': '../../Lib/Windows/VMProtectSDK32.dll'}
        self.manifest = {'version': VERSION, 'archive_sha256': '0' * 64, 'files': files, 'removed': {}}
        (self.root / 'extraction-manifest.json').write_text(json.dumps(self.manifest))

    def sdk(self):
        with redirect_stdout(io.StringIO()):
            return package_sdk(self.root, self.assets)

    def examples(self):
        for name, project in PROJECTS.items():
            with zipfile.ZipFile(self.assets / f'{name}.zip', 'x') as archive:
                for member in project.required:
                    contents = {member: b'build output'}
                    if member.endswith('.app'):
                        contents = {
                            f'{member}/Contents/Info.plist': plistlib.dumps({'CFBundleExecutable': 'Example'}),
                            f'{member}/Contents/MacOS/Example': b'executable',
                        }
                    for path, data in contents.items():
                        info = zipfile.ZipInfo(path)
                        info.create_system = 3
                        info.external_attr = (stat.S_IFREG | 0o755) << 16
                        archive.writestr(info, data)

    def test_sdk_expands_links_preserves_scripts_and_excludes_unlisted_files(self):
        (self.root / 'Examples/Unlisted.exe').write_bytes(b'exclude')
        with zipfile.ZipFile(self.sdk()) as archive:
            self.assertEqual(set(archive.namelist()), set(self.manifest['files']) | {'extraction-manifest.json'})
            for name, record in self.manifest['files'].items():
                self.assertEqual(hashlib.sha256(archive.read(name)).hexdigest(), record['sha256'])
                self.assertTrue(stat.S_ISREG(archive.getinfo(name).external_attr >> 16))
            self.assertEqual(stat.S_IMODE(archive.getinfo('Examples/Scripts/Project1.exe').external_attr >> 16), 0o755)

    def test_sdk_rejects_changed_bytes_before_creating_zip(self):
        (self.root / 'Include/C/VMProtectSDK.h').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'Changed original SDK bytes'):
            self.sdk()
        self.assertEqual(list(self.assets.iterdir()), [])

    def test_manifest_version_controls_sdk_archive_name(self):
        self.manifest['version'] = '9.8.7.6'
        (self.root / 'extraction-manifest.json').write_text(json.dumps(self.manifest))
        self.assertEqual(self.sdk().name, 'vmpsdk-9.8.7.6.zip')

    def test_manifest_must_have_a_valid_version(self):
        for version in (None, '', '3.5', '../3.5.0.1249'):
            with self.subTest(version=version):
                self.manifest['version'] = version
                (self.root / 'extraction-manifest.json').write_text(json.dumps(self.manifest))
                with self.assertRaisesRegex(ValueError, 'Invalid SDK version'):
                    sdk_version(self.root)

    def test_sdk_does_not_overwrite_an_existing_archive(self):
        output = self.sdk()
        content = output.read_bytes()
        with self.assertRaises(FileExistsError):
            self.sdk()
        self.assertEqual(output.read_bytes(), content)

    def test_release_preserves_all_example_zips_and_covers_them_with_checksums(self):
        self.examples()
        before = {path.name: path.read_bytes() for path in self.assets.iterdir()}
        with redirect_stdout(io.StringIO()):
            prepare(self.root, self.assets)
        for name, content in before.items():
            self.assertEqual((self.assets / name).read_bytes(), content)
        names = example_names() | {f'vmpsdk-{VERSION}.zip'}
        self.assertEqual({path.name for path in self.assets.iterdir()}, names | {'SHA256SUMS'})
        self.assertEqual((self.assets / 'SHA256SUMS').read_text(), checksums(self.assets, names))

    def test_missing_example_stops_release_preparation(self):
        self.examples()
        (self.assets / 'windows-x86-ddk-licensing.zip').unlink()
        with self.assertRaisesRegex(ValueError, 'windows-x86-ddk-licensing.zip'):
            prepare(self.root, self.assets)
        self.assertFalse((self.assets / f'vmpsdk-{VERSION}.zip').exists())

    def test_corrupt_example_stops_release_preparation(self):
        self.examples()
        (self.assets / 'windows-x86-ddk-licensing.zip').write_bytes(b'not a ZIP')
        with self.assertRaises(zipfile.BadZipFile):
            prepare(self.root, self.assets)

    def test_extra_wrapper_directory_stops_release_preparation(self):
        self.examples()
        with zipfile.ZipFile(self.assets / 'windows-x86-ddk-licensing.zip', 'w') as archive:
            archive.writestr('wrapper/TestApp.sys', b'output')
        with self.assertRaisesRegex(ValueError, 'Unexpected example member'):
            prepare(self.root, self.assets)

    def test_unix_executable_permissions_are_required(self):
        self.examples()
        with zipfile.ZipFile(self.assets / 'linux-x64-gcc-markers.zip', 'w') as archive:
            for name in PROJECTS['linux-x64-gcc-markers'].required:
                archive.writestr(name, b'output without executable mode')
        with self.assertRaisesRegex(ValueError, 'Unix executable permission missing'):
            prepare(self.root, self.assets)

    def test_published_release_and_draft_for_another_commit_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'published release'):
            check_draft({'draft': False}, 'commit', set())
        with self.assertRaisesRegex(ValueError, 'another commit'):
            check_draft({'draft': True, 'target_commitish': 'old'}, 'commit', set())

    def test_uploaded_assets_require_matching_digests_and_complete_names(self):
        path = self.assets / 'example.zip'
        path.write_bytes(b'content')
        release = {'draft': True, 'target_commitish': 'commit', 'assets': [{
            'name': path.name, 'size': path.stat().st_size, 'state': 'uploaded',
            'digest': f'sha256:{hashlib.sha256(path.read_bytes()).hexdigest()}',
        }]}
        verify_uploaded(release, 'commit', self.assets, {path.name})
        with self.assertRaisesRegex(ValueError, 'incomplete'):
            verify_uploaded(release, 'commit', self.assets, {path.name, 'missing.zip'})
        path.write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'differs from local file'):
            verify_uploaded(release, 'commit', self.assets, {path.name})


class ExtractionVersionTests(unittest.TestCase):
    def test_version_is_required_even_for_a_versioned_filename(self):
        result = subprocess.run([sys.executable, str(REPO / 'extract.py'), f'VMProtectSDK-{VERSION}.zip'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('required: --version', result.stderr)

    def test_manual_version_is_recorded_independently_of_filename(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            script = root / 'extract.py'
            shutil.copyfile(REPO / 'extract.py', script)
            archive = root / 'VMProtectSDK-1.2.3.4.zip'
            with zipfile.ZipFile(archive, 'w') as output:
                for name in ('Include/C/VMProtectSDK.h', 'Lib/Linux/libVMProtectSDK32.so',
                             'Lib/Linux/libVMProtectSDK64.so', 'Examples/Code Markers/GCC/Project1.cpp'):
                    output.writestr(name, b'original content')
            subprocess.run([sys.executable, str(script), str(archive), '--version', VERSION],
                           check=True, capture_output=True, text=True)
            manifest = json.loads((root / 'extraction-manifest.json').read_text())
            self.assertEqual(manifest['version'], VERSION)
            self.assertNotIn('archive', manifest)
            self.assertEqual(manifest['archive_sha256'], hashlib.sha256(archive.read_bytes()).hexdigest())


if __name__ == '__main__':
    unittest.main()

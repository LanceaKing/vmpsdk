"""Check archive contents, dependencies, and executable permissions."""
from contextlib import redirect_stdout
import io
import os
from pathlib import Path
import stat
from tempfile import TemporaryDirectory
import unittest
import zipfile

from package import package


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.artifacts = self.root / 'artifacts'
        self.archives = self.root / 'archives'

    def file(self, name, content=b'build output', mode=0o644):
        path = self.artifacts / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        path.chmod(mode)
        return path

    def build_zip(self, name):
        with redirect_stdout(io.StringIO()):
            return package(name, self.artifacts, self.archives)

    def test_masm_files_are_at_root_and_other_outputs_are_excluded(self):
        self.file('masm-x86/Project1.exe', b'new executable')
        self.file('masm-x86/VMProtectSDK32.dll', b'original SDK')
        self.file('masm-x86/Project1.obj')
        self.file('masm-x86/build.log')
        self.file('masm-x86/AnotherProject.exe')
        output = self.build_zip('windows-x86-masm-markers')
        self.assertEqual(output.name, 'windows-x86-masm-markers.zip')
        with zipfile.ZipFile(output) as archive:
            self.assertEqual(set(archive.namelist()), {'Project1.exe', 'VMProtectSDK32.dll'})
            self.assertEqual(archive.read('Project1.exe'), b'new executable')
            self.assertEqual(archive.read('VMProtectSDK32.dll'), b'original SDK')

    def test_missing_runtime_library_stops_packaging(self):
        self.file('masm-x86/Project1.exe')
        with self.assertRaisesRegex(ValueError, 'VMProtectSDK32.dll'):
            self.build_zip('windows-x86-masm-markers')
        self.assertFalse(self.archives.exists())

    def test_empty_executable_stops_packaging(self):
        self.file('masm-x86/Project1.exe', b'')
        self.file('masm-x86/VMProtectSDK32.dll')
        with self.assertRaisesRegex(ValueError, 'Project1.exe'):
            self.build_zip('windows-x86-masm-markers')

    def test_native_keygen_library_and_usage_are_separate(self):
        for name in ['KeyGen32.dll', 'KeyGen32.lib', 'KeyGenExample.exe', 'KeyGen32.exp', 'KeyGen.res']:
            self.file(f'keygen-x86/{name}')
        for project, expected in [
            ('keygen', {'KeyGen32.dll', 'KeyGen32.lib'}),
            ('keygen-usage', {'KeyGenExample.exe', 'KeyGen32.dll'}),
        ]:
            with self.subTest(project=project):
                output = self.build_zip(f'windows-x86-msvc-{project}')
                with zipfile.ZipFile(output) as archive:
                    self.assertEqual(set(archive.namelist()), expected)

    def test_delphi_projects_include_maps_and_their_own_runtime(self):
        for project, executable, runtime in (
            ('markers', 'Project1', 'VMProtectSDK32.dll'),
            ('licensing', 'TestApp', 'VMProtectSDK32.dll'),
            ('keygen-usage', 'KeyGenExample', 'KeyGen32.dll'),
        ):
            with self.subTest(project=project):
                folder = f'{project}-delphi-x86'
                expected = {f'{executable}.exe', f'{executable}.map', runtime}
                for name in expected | {'Unit1.dcu', 'TestApp.res', 'build.log', 'AnotherProject.exe'}:
                    self.file(f'{folder}/{name}')
                output = self.build_zip(f'windows-x86-delphi-{project}')
                self.assertEqual(output.name, f'windows-x86-delphi-{project}.zip')
                with zipfile.ZipFile(output) as archive:
                    self.assertEqual(set(archive.namelist()), expected)

    def test_delphi_keygen_requires_its_runtime(self):
        self.file('keygen-usage-delphi-x86/KeyGenExample.exe')
        self.file('keygen-usage-delphi-x86/KeyGenExample.map')
        with self.assertRaisesRegex(ValueError, 'KeyGen32.dll'):
            self.build_zip('windows-x86-delphi-keygen-usage')

    def test_net_any_architecture_and_separate_projects(self):
        for name in ['VMProtect.KeyGen.dll', 'VMProtect.KeyGen.pdb', 'Usage.exe', 'Usage.exe.config', 'Usage.pdb']:
            self.file(f'keygen-net/{name}')
        with zipfile.ZipFile(self.build_zip('windows-any-net-keygen')) as archive:
            self.assertEqual(set(archive.namelist()), {'VMProtect.KeyGen.dll', 'VMProtect.KeyGen.pdb'})
        with zipfile.ZipFile(self.build_zip('windows-any-net-keygen-usage')) as archive:
            self.assertEqual(set(archive.namelist()), {
                'VMProtect.KeyGen.dll', 'VMProtect.KeyGen.pdb', 'Usage.exe', 'Usage.exe.config', 'Usage.pdb'})

    def test_runtime_manifest_and_debug_files_are_preserved(self):
        expected = {'TestApp.exe', 'VMProtectSDK64.dll', 'TestApp.exe.manifest', 'TestApp.map', 'TestApp.pdb'}
        for name in expected | {'Resources.res', 'TestApp.ilk'}:
            self.file(f'licensing-x64/{name}')
        with zipfile.ZipFile(self.build_zip('windows-x64-msvc-licensing')) as archive:
            self.assertEqual(set(archive.namelist()), expected)

    @unittest.skipIf(os.name == 'nt', 'Unix permission and symlink metadata')
    def test_unix_mode_and_app_bundle_structure(self):
        self.file('gcc-x64/Project1', mode=0o755)
        self.file('gcc-x64/libVMProtectSDK.dylib')
        with zipfile.ZipFile(self.build_zip('macos-x64-gcc-markers')) as archive:
            self.assertEqual(set(archive.namelist()), {'Project1', 'libVMProtectSDK.dylib'})
            self.assertEqual(stat.S_IMODE(archive.getinfo('Project1').external_attr >> 16), 0o755)
        self.file('Project1.app/Contents/MacOS/Project1', mode=0o755)
        self.file('Project1.app/Contents/Info.plist')
        self.file('Project1.app/Contents/MacOS/libVMProtectSDK.dylib')
        self.file('Project1.app.dSYM/Contents/Resources/DWARF/Project1')
        link = self.artifacts / 'Project1.app/Contents/MacOS/program'
        link.symlink_to('Project1')
        with zipfile.ZipFile(self.build_zip('macos-x64-xcode-markers')) as archive:
            self.assertEqual({name.split('/')[0] for name in archive.namelist()}, {'Project1.app', 'Project1.app.dSYM'})
            info = archive.getinfo('Project1.app/Contents/MacOS/Project1')
            self.assertEqual(stat.S_IMODE(info.external_attr >> 16), 0o755)
            info = archive.getinfo('Project1.app/Contents/MacOS/program')
            self.assertTrue(stat.S_ISLNK(info.external_attr >> 16))
            self.assertEqual(archive.read(info), b'Project1')

    def test_existing_zip_is_not_overwritten(self):
        self.file('masm-x86/Project1.exe')
        self.file('masm-x86/VMProtectSDK32.dll')
        output = self.build_zip('windows-x86-masm-markers')
        original = output.read_bytes()
        with self.assertRaises(FileExistsError):
            self.build_zip('windows-x86-masm-markers')
        self.assertEqual(output.read_bytes(), original)


if __name__ == '__main__':
    unittest.main()

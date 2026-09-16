$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sdk = Join-Path $root '.build/vb6'
$downloads = Join-Path $root '.build/downloads/vb6'
$archive = Join-Path $downloads 'vb6-portable.zip'
$revision = '01ecb4d13e5ec00c8986dfec86dce46f923a4f3b'
$sha256 = '7d58685bd0b6c6313a5c95200e9250d15288aae47bd124189dcf6f98fd9c9576'
if (Test-Path $sdk) { throw "Refusing to overwrite existing VB6 toolchain: $sdk" }
New-Item -ItemType Directory -Force -Path $downloads | Out-Null
if (!(Test-Path $archive)) {
    Invoke-WebRequest "https://codeload.github.com/sdksmate/vb6-portable/zip/$revision" -OutFile $archive
}
if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne $sha256) {
    throw 'VB6 archive SHA-256 mismatch'
}
Expand-Archive -LiteralPath $archive -DestinationPath $downloads -Force
$source = Join-Path $downloads "vb6-portable-$revision"
New-Item -ItemType Directory -Path $sdk | Out-Null
# Use the compiler directly, without the portable launcher or registry installer.
# Do not install the bundled old MSVCRT over the Windows runtime.
foreach ($name in @(
    'Vb6.exe', 'Vb6.olb', 'Vb6ext.olb', 'Vb6debug.dll', 'Vb6ide.dll',
    'Vba6.dll', 'Vbaexe6.lib', 'C2.exe', 'Link.exe', 'Mspdb60.dll',
    'Mso97rt.dll', 'Mrt7enu.dll', 'ENTDAT.DLL', 'PRODAT.DLL', 'LRNDAT.DLL',
    'Dao350.dll'
)) {
    Copy-Item (Join-Path $source $name) $sdk
}
# VBA6 exports a type library, not DllRegisterServer. Register the type libraries
# from a 32-bit process, as the original VB6 installer does.
$registration = Join-Path $sdk 'register.ps1'
@'
$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class VB6TypeLibrary {
    [DllImport("oleaut32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    public static extern void LoadTypeLibEx(string path, int kind, out IntPtr library);
}
"@
foreach ($name in @('Vba6.dll', 'Vb6.olb', 'Vb6ext.olb')) {
    $library = [IntPtr]::Zero
    [VB6TypeLibrary]::LoadTypeLibEx((Join-Path $PSScriptRoot $name), 1, [ref]$library)
    [void][Runtime.InteropServices.Marshal]::Release($library)
}
'@ | Set-Content -Encoding ascii $registration
$process = Start-Process "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$registration`"" -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "VB6 type library registration exited with $($process.ExitCode)" }
Write-Host "VB6 $((Get-Item "$sdk\Vb6.exe").VersionInfo.FileVersion) ready: $sdk"

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
# Preserve the whole package so implicit compiler dependencies are not omitted.
# Only remove the archive's outer directory; do not run its portable launcher.
Expand-Archive -LiteralPath $archive -DestinationPath $downloads -Force
Move-Item (Join-Path $downloads "vb6-portable-$revision") $sdk
# The portable package omits the data-formatting COM server used by intrinsic
# TextBox and Label controls, even when the forms do not bind to a database.
$runtime = Join-Path $downloads 'VB60SP6-KB2708437-x86-ENU.msi'
if (!(Test-Path $runtime)) {
    Invoke-WebRequest 'https://download.microsoft.com/download/5/6/3/5635D6A9-885E-4C80-A2E7-8A7F4488FBF1/VB60SP6-KB2708437-x86-ENU.msi' -OutFile $runtime
}
if ((Get-FileHash $runtime -Algorithm SHA256).Hash -ne '350602b2e084b39c97d1394c8594b18e41ef622315d4a9635c5e8ea6aa977b5e') {
    throw 'VB6 runtime update SHA-256 mismatch'
}
# Let Windows Installer install and register all runtime update features.
$logs = Join-Path $root '.build/logs/vb6'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$installLog = Join-Path $logs 'runtime-install.log'
$arguments = '/i "{0}" /qn /norestart ADDLOCAL=ALL /L*v "{1}"' -f $runtime, $installLog
$process = Start-Process "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $arguments -Wait -PassThru
try {
    if ($process.ExitCode -notin @(0, 3010)) {
        if (Test-Path $installLog) { Get-Content $installLog -Tail 80 | Write-Host }
        throw "VB6 runtime installer exited with $($process.ExitCode); see $installLog"
    }
    Write-Host "VB6 runtime installer exited with $($process.ExitCode)"
    if ($process.ExitCode -eq 3010) { Write-Warning 'VB6 runtime update requested a restart; automatic restart is disabled.' }
} finally { $process.Dispose() }
# VBA6 exports a type library, not DllRegisterServer. Register the type libraries
# from a 32-bit process, as the original VB6 installer does.
$registration = @'
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
    [VB6TypeLibrary]::LoadTypeLibEx((Join-Path $env:VMPSDK_VB6_DIR $name), 1, [ref]$library)
    [void][Runtime.InteropServices.Marshal]::Release($library)
}
# Core setup records 776-778 from VB98ENT.STF. Without these installation
# records VB6 starts as Working Model Edition and cannot run /make.
# https://github.com/gdsestimating/vb6-install-recipe/blob/70ef8f17ce744b9affadf044b3e2e68a7846570f/vb98ent_minimal.stf#L726-L728
$coreLicenses = @{
    '6000720D-F342-11D1-AF65-00A0C90DCA10' = 'kefeflhlhlgenelerfleheietfmflelljeqf'
    '74872840-703A-11d1-A3AF-00A0C90F26FA' = 'mninuglgknogtgjnthmnggjgsmrmgniglish'
    '74872841-703A-11d1-A3AF-00A0C90F26FA' = 'klglsejeilmereglrfkleeheqkpkelgejgqf'
}
foreach ($id in $coreLicenses.Keys) {
    $key = [Microsoft.Win32.Registry]::ClassesRoot.CreateSubKey("Licenses\$id")
    try { $key.SetValue('', $coreLicenses[$id]) } finally { $key.Dispose() }
}
'@
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($registration))
$process = Start-Process "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList '-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded `
    -Environment @{VMPSDK_VB6_DIR=$sdk} -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "VB6 registration exited with $($process.ExitCode)" }
Write-Host "VB6 $((Get-Item "$sdk\Vb6.exe").VersionInfo.FileVersion) ready: $sdk"

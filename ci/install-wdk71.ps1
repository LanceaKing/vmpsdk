$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
# The original make.bat uses this exact path.
$sdk = 'C:\WinDDK\7600.16385.1'
if (Test-Path $sdk) { throw "Refusing to overwrite an existing WDK: $sdk" }
$downloads = Join-Path $root '.build/downloads/wdk-7.1'
$media = Join-Path $root '.build/wdk71-media'
$logs = Join-Path $root '.build/logs/wdk71'
New-Item -ItemType Directory -Force $downloads, $logs | Out-Null
$iso = Join-Path $downloads 'GRMWDK_EN_7600_1.ISO'
$url = 'https://download.microsoft.com/download/4/A/2/4A25C7D5-EFBE-4182-B6A9-AE6850409A78/GRMWDK_EN_7600_1.ISO'
$sha256 = '5edc723b50ea28a070cad361dd0927df402b7a861a036bbcf11d27ebba77657d'
if (!(Test-Path $iso)) {
    & curl.exe --fail --location --retry 3 --output $iso $url
    if ($LASTEXITCODE -ne 0) { throw "WDK download failed: $LASTEXITCODE" }
} else {
    Write-Host 'Using cached WDK 7.1 ISO; skipping download and verifying its digest'
}
if ((Get-Item $iso).Length -ne 649877504 -or (Get-FileHash $iso -Algorithm SHA256).Hash -ne $sha256) {
    throw "WDK ISO size or SHA-256 mismatch: $iso"
}
Write-Host "Verified WDK 7.1 ISO SHA-256: $sha256"

$sevenZip = Join-Path $env:ProgramFiles '7-Zip/7z.exe'
if (!(Test-Path $sevenZip)) { throw '7-Zip is required to open the WDK ISO' }
# Each MSI and its external cabinet is installed in full. The SKOM packaging
# manifests in the ISO supply SOURCEINSTALL and DEFAULT_INSTALL_DIR1.
$packages = @('buildtools_x86fre', 'headers', 'libs_x86fre', 'wxplibs_x86fre')
$members = foreach ($package in $packages) { "WDK/$package.msi"; "WDK/${package}_cab001.cab" }
& $sevenZip x -y "-o$media" $iso @members
if ($LASTEXITCODE -ne 0) { throw "WDK ISO extraction failed: $LASTEXITCODE" }
foreach ($package in $packages) {
    $msi = Join-Path $media "WDK/$package.msi"
    $log = Join-Path $logs "$package.log"
    $arguments = '/i "{0}" /qn /norestart ADDLOCAL=ALL SOURCEINSTALL=1 DEFAULT_INSTALL_DIR1="{1}" /l*v "{2}"' -f $msi, $sdk, $log
    Write-Host "Installing WDK component: $package"
    $process = Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) {
        if (Test-Path $log) { Get-Content $log -Tail 100 | Write-Host }
        throw "WDK component $package installation failed: $($process.ExitCode)"
    }
    Write-Host "Installed $package (exit $($process.ExitCode))"
    if ($process.ExitCode -eq 3010) { Write-Warning 'WDK requested a restart; the runner will not reboot' }
}
foreach ($file in @('bin/setenv.bat', 'bin/makefile.def', 'bin/x86/nmake.exe',
                    'bin/x86/x86/cl.exe', 'bin/x86/x86/link.exe', 'inc/ddk/ntddk.h', 'lib/wxp/i386/ntoskrnl.lib')) {
    if (!(Test-Path (Join-Path $sdk $file))) { throw "Missing WDK file after installation: $file" }
}
Write-Host "WDK 7.1 ready: $sdk"

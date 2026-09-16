$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sdk = 'C:\WinDDK\7600.16385.1'
$source = Join-Path $root '.build/work/Examples/Licensing/DDK'
$dest = Join-Path $root '.build/artifacts/licensing-ddk-x86'
if (!(Test-Path "$sdk/bin/setenv.bat")) { throw 'WDK 7.1 missing; run ci/install-wdk71.ps1 first' }
if (!(Test-Path "$source/make.bat")) { throw 'Build tree missing; run ci/prepare.py first' }
if (Test-Path $dest) { throw "Refusing to overwrite existing DDK output: $dest" }
foreach ($name in @('TestApp.sys', 'TestApp.map', 'TestApp.pdb')) {
    if (Get-ChildItem $source -Recurse -File -Filter $name) { throw "Stale DDK build output: $name" }
}

Push-Location $source
try {
    # The unchanged batch file selects wxp/free/no_oacr and runs nmake against
    # the original MAKEFILE and SOURCES. Do not use the runner's MSVC toolchain.
    & cmd.exe /d /c 'call make.bat'
    if ($LASTEXITCODE -ne 0) { throw "DDK build failed: $LASTEXITCODE" }
} finally { Pop-Location }

New-Item -ItemType Directory -Path $dest | Out-Null
foreach ($name in @('TestApp.sys', 'TestApp.map', 'TestApp.pdb')) {
    $files = @(Get-ChildItem $source -Recurse -File -Filter $name)
    if ($files.Count -ne 1 -or $files[0].Length -eq 0) { throw "Expected one nonempty DDK output: $name" }
    Copy-Item $files[0].FullName (Join-Path $dest $name)
}
Copy-Item (Join-Path $root '.build/work/Lib/Windows/VMProtectDDK32.sys') $dest

$dump = & "$sdk/bin/x86/x86/link.exe" /dump /headers /imports "$dest/TestApp.sys"
if ($LASTEXITCODE -ne 0) { throw "DDK image inspection failed: $LASTEXITCODE" }
$dump | Write-Host
$text = $dump -join "`n"
foreach ($pattern in @('14C machine \(x86\)', '1 subsystem \(Native\)', 'VMProtectDDK32\.sys', 'ntoskrnl\.exe')) {
    if ($text -notmatch $pattern) { throw "Unexpected DDK image; missing: $pattern" }
}
if ($text -match '(?i)\b(?:kernel32|user32|msvcrt|VMProtectSDK32)\.dll\b') {
    throw 'DDK image unexpectedly imports a user-mode runtime'
}
Write-Host 'PASS: x86 native TestApp.sys with VMProtectDDK32.sys and ntoskrnl.exe imports'

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sdk = Join-Path $root '.build/bcb'
$downloads = Join-Path $root '.build/downloads/bcb'
$unpack = Join-Path $root '.build/bcb-unpack'
if (Test-Path $sdk) { throw "Refusing to overwrite existing C++Builder toolchain: $sdk" }
$manifest = Get-Content "$PSScriptRoot/bcb-toolchain.json" -Raw | ConvertFrom-Json -AsHashtable
New-Item -ItemType Directory -Force $downloads, $sdk | Out-Null
# Original payloads from the official XE5 Update 2 offline installation (4.82 GiB).
# The directory mapping and archive passwords come from its Install/Setup.exe.
# Every package is checked on both downloads and cache restores.
foreach ($package in $manifest.packages) {
    $archive = Join-Path $downloads "$($package.name).7zip"
    if (!(Test-Path $archive)) {
        & curl.exe --fail --location --retry 3 --connect-timeout 30 --max-time 300 --max-filesize $package.size `
            --output $archive "$($manifest.url)/$($package.name).7zip"
        if ($LASTEXITCODE -ne 0) { throw "C++Builder download failed: $($package.name)" }
    }
    if ((Get-Item $archive).Length -ne $package.size -or (Get-FileHash $archive -Algorithm SHA256).Hash -ne $package.sha256) {
        throw "C++Builder package size/SHA-256 mismatch: $($package.name)"
    }
    & 7z x -y -bso0 "-p$($package.password)" "-o$unpack" $archive
    if ($LASTEXITCODE -ne 0) { throw "C++Builder extraction failed: $($package.name)" }
    foreach ($entry in $package.directories.GetEnumerator()) {
        $source = Join-Path $unpack "$($package.name)/$($entry.Key)"
        $dest = Join-Path $sdk $entry.Value
        if (!(Test-Path $source -PathType Container)) { throw "Missing toolchain directory: $source" }
        New-Item -ItemType Directory -Force $dest | Out-Null
        Copy-Item "$source/*" $dest -Recurse -Force
    }
}
foreach ($file in @('bin/bcc32.exe', 'bin/ilink32.exe', 'bin/rlink32.dll', 'bin/implib.exe', 'bin/brcc32.exe',
    'bin/default_app.manifest', 'include/windows/vcl/vcl.h', 'lib/win32/release/vcl.lib', 'lib/win32/release/rtl.lib')) {
    if (!(Test-Path "$sdk/$file")) { throw "Incomplete C++Builder toolchain: $file" }
}
Write-Host "C++Builder XE5 Update 2 toolchain: $sdk"

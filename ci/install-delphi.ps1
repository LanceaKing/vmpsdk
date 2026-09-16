$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sdk = Join-Path $root '.build/delphi'
$downloads = Join-Path $root '.build/downloads/delphi'
$stem = 'Delphi7_Lite_Full_Edition_Setup_7.3.4.3_Build_20110801'
$archive = Join-Path $downloads "$stem.rar"
$installer = Join-Path $downloads "$stem/$stem.exe"
if (Test-Path $sdk) { throw "Refusing to overwrite existing Delphi installation: $sdk" }
New-Item -ItemType Directory -Force -Path $downloads | Out-Null
if (!(Test-Path $archive)) {
    Invoke-WebRequest "https://downloads.sourceforge.net/project/c0de-s/$stem.rar" -OutFile $archive
}
if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne '352d0c13c784d85b97f3a97ce2fa07b44f3ee00b4a0a7b9107db1928873eb129') {
    throw 'Delphi 7 Lite archive SHA-256 mismatch'
}
& 7z x -y $archive "-o$downloads"
if ($LASTEXITCODE -ne 0) { throw "7-Zip exited with $LASTEXITCODE" }
if ((Get-FileHash $installer -Algorithm SHA256).Hash -ne 'e413ecd2615e24fb3a3a60555a6afdaccb812c70c3b693e709859928ecc878da') {
    throw 'Delphi 7 Lite installer SHA-256 mismatch'
}
$logs = Join-Path $root '.build/logs/delphi'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$installLog = Join-Path $logs 'install.log'
# This 78 MB installer is installed in full, not unpacked as a portable compiler.
$arguments = '/SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /TYPE=full /TASKS="" /LANG=en /DIR="{0}" /LOG="{1}"' -f $sdk, $installLog
$process = Start-Process $installer -ArgumentList $arguments -PassThru
try {
    if (!$process.WaitForExit(600000)) {
        $process.Kill($true)
        $process.WaitForExit()
        throw 'Delphi installation timed out after 10 minutes'
    }
    if ($process.ExitCode -ne 0) { throw "Delphi installer exited with $($process.ExitCode)" }
    foreach ($file in @('Bin\dcc32.exe', 'Bin\brcc32.exe', 'Bin\rlink32.dll', 'Lib\System.dcu', 'Lib\Forms.dcu')) {
        $path = Join-Path $sdk $file
        if (!(Test-Path $path) -or (Get-Item $path).Length -eq 0) { throw "Missing Delphi toolchain file: $path" }
    }
} catch {
    if (Test-Path $installLog) { Get-Content $installLog -Tail 80 | Write-Host }
    throw
} finally { $process.Dispose() }
Write-Host "Delphi 7 ready: $sdk"

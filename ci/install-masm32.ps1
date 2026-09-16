$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
# The unmodified sample and MASM32's library builder use \masm32 on the current drive.
$sdk = Join-Path ([IO.Path]::GetPathRoot($root)) 'masm32'
$downloads = Join-Path $root '.build/downloads/masm32'
$archive = Join-Path $downloads 'm32v9r.zip'
$sha256 = '000a660fce59e619ea608a889b9ae1e43ad1dfcb81ef79ca22a0d67503cd0205'
function Run([string]$Tool, [string[]]$Arguments) {
    & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Tool exited with $LASTEXITCODE" }
}
if (Test-Path $sdk) { throw "Refusing to overwrite existing MASM32 SDK: $sdk" }
New-Item -ItemType Directory -Force -Path $downloads | Out-Null
if (!(Test-Path $archive)) {
    Invoke-WebRequest 'https://www.codingcrew.de/masm32/download/m32v9r.zip' -OutFile $archive
}
if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne $sha256) {
    throw 'MASM32 v9 archive SHA-256 mismatch'
}
Expand-Archive -LiteralPath $archive -DestinationPath $downloads -Force
# install.exe contains a standard 7z archive. Force that format to extract it
# without running the GUI installer. Its PE trailer produces a harmless warning.
Run '7z' @('x', '-t7z', '-y', "$downloads\install.exe", "-o$sdk")

# Replay the library-building part of installation, with checked exit codes and
# no pause/test GUI. Only these Windows import libraries are used by Project1.inc.
Push-Location "$sdk\include"
try {
    foreach ($name in @('gdi32', 'user32', 'kernel32', 'comctl32', 'comdlg32', 'shell32', 'oleaut32')) {
        Run '.\inc2l.exe' @("$name.inc")
        if (!(Test-Path "$name.lib")) { throw "MASM32 did not generate $name.lib" }
        Copy-Item "$name.lib" "$sdk\lib\"
    }
} finally { Pop-Location }
Push-Location "$sdk\m32lib"
try {
    Get-ChildItem '*.asm' | Sort-Object Name | ForEach-Object { $_.Name } |
        Set-Content -Encoding ascii 'ml.rsp'
    Run "$sdk\bin\ml.exe" @('/c', '/coff', '@ml.rsp')
    Run "$sdk\bin\link.exe" @('-lib', '*.obj', "/out:$sdk\lib\masm32.lib")
    if (!(Test-Path "$sdk\lib\masm32.lib")) { throw 'Missing MASM32 runtime library' }
    Copy-Item 'masm32.inc' "$sdk\include\"
} finally { Pop-Location }
Write-Host "MASM32 v9 ready: $sdk"

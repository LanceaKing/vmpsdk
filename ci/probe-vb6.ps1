$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$probe = Join-Path $root '.build/logs/vb6/probe'
New-Item -ItemType Directory -Force $probe | Out-Null
@'
Attribute VB_Name = "Main"
Public Sub Main()
End Sub
'@ | Set-Content -Encoding ascii "$probe/Main.bas"
@'
Type=Exe
Module=Main; Main.bas
Startup="Sub Main"
ExeName32="Probe.exe"
Name="Probe"
CompilationType=0
'@ | Set-Content -Encoding ascii "$probe/Probe.vbp"
$compiler = "$root/.build/vb6/Vb6.exe"
$start = Get-Date
foreach ($layer in @('', 'WinXPSP3')) {
    $env:__COMPAT_LAYER = $layer
    $p = Start-Process $compiler -WorkingDirectory $probe -PassThru -ArgumentList @(
        '/make', "`"$probe/Probe.vbp`"", '/out', "`"$probe/build-$layer.log`"", '/outdir', "`"$probe`""
    )
    if (!$p.WaitForExit(15000)) { $p.Kill($true); $p.WaitForExit() }
    Write-Host "[DEBUG-vb6] Minimal project layer '$layer': exit $($p.ExitCode); EXE $(Test-Path "$probe/Probe.exe")"
    if (Test-Path "$probe/build-$layer.log") { Get-Content "$probe/build-$layer.log" }
    if (Test-Path "$probe/Probe.exe") { Remove-Item "$probe/Probe.exe" }
}
Remove-Item Env:__COMPAT_LAYER
Start-Sleep 3
Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$start} -ErrorAction SilentlyContinue |
    Where-Object Message -Match 'vb6|vba6|c2.exe' |
    Format-List TimeCreated, Id, Message | Out-String | Tee-Object "$probe/events.txt" | Write-Host

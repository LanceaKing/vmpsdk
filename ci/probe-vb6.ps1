$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$probe = Join-Path $root '.build/logs/vb6/probe'
New-Item -ItemType Directory -Force $probe | Out-Null
@'
Attribute VB_Name = "Module1"
Public Sub Main()
End Sub
'@ | Set-Content -Encoding ascii "$probe/Main.bas"
@'
Type=Exe
Module=Module1; Main.bas
Startup="Sub Main"
ExeName32="Probe.exe"
Name="Probe"
CompilationType=0
'@ | Set-Content -Encoding ascii "$probe/Probe.vbp"
$compiler = "$root/.build/vb6/Vb6.exe"
$start = (Get-Date).AddMinutes(-5)
foreach ($case in @(
    @{Name='minimal'; Layer=''; Project="$probe/Probe.vbp"; Exe='Probe.exe'},
    @{Name='minimal-xp'; Layer='WinXPSP3'; Project="$probe/Probe.vbp"; Exe='Probe.exe'},
    @{Name='markers-xp'; Layer='WinXPSP3'; Project="$root/.build/work/Examples/Code Markers/VB6/Project1.vbp"; Exe='Project1.exe'}
)) {
    $env:__COMPAT_LAYER = $case.Layer
    $p = Start-Process $compiler -WorkingDirectory $probe -PassThru -ArgumentList @(
        '/make', "`"$($case.Project)`"", '/out', "`"$probe/$($case.Name).log`"", '/outdir', "`"$probe`""
    )
    if (!$p.WaitForExit(15000)) { $p.Kill($true); $p.WaitForExit() }
    Write-Host "[DEBUG-vb6] $($case.Name): exit $($p.ExitCode); EXE $(Test-Path "$probe/$($case.Exe)")"
    if (Test-Path "$probe/$($case.Name).log") { Get-Content "$probe/$($case.Name).log" }
    if (Test-Path "$probe/$($case.Exe)") { Remove-Item "$probe/$($case.Exe)" }
}
Remove-Item Env:__COMPAT_LAYER
Start-Sleep 3
Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$start} -ErrorAction SilentlyContinue |
    Where-Object Message -Match 'vb6|vba6|c2.exe' |
    Format-List TimeCreated, Id, Message | Out-String | Tee-Object "$probe/events.txt" | Write-Host

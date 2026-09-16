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
$reference = Get-Content "$root/.build/work/Examples/Code Markers/VB6/Project1.vbp" | Where-Object { $_ -like 'Reference=*' }
$minimal = Get-Content "$probe/Probe.vbp" -Raw
($minimal + "`r`n$reference") | Set-Content -Encoding ascii "$probe/RefBroken.vbp"
($minimal + "`r`n" + ($reference -replace '#[^#]+#OLE Automation$', "#$env:SystemRoot\SysWOW64\stdole2.tlb#OLE Automation")) |
    Set-Content -Encoding ascii "$probe/RefSystem.vbp"
foreach ($case in @(
    @{Name='ref-broken'; Layer=''; Project="$probe/RefBroken.vbp"; Exe='Probe.exe'},
    @{Name='ref-system'; Layer=''; Project="$probe/RefSystem.vbp"; Exe='Probe.exe'}
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
# Satisfy the original reference path without editing the project.
$projectDir = "$root/.build/work/Examples/Code Markers/VB6"
$alias = [IO.Path]::GetFullPath((Join-Path $projectDir ($reference.Split('#')[3])))
if (!(Test-Path $alias)) {
    New-Item -ItemType Directory -Force (Split-Path $alias) | Out-Null
    Copy-Item "$env:SystemRoot/SysWOW64/stdole2.tlb" $alias
}
Write-Host "[DEBUG-vb6] OLE reference alias: $alias"
$p = Start-Process $compiler -WorkingDirectory $projectDir -PassThru -ArgumentList (
    '/make Project1.vbp /out "{0}" /outdir "{1}"' -f "$probe/markers-alias.log", $probe
)
if (!$p.WaitForExit(15000)) { $p.Kill($true); $p.WaitForExit() }
Write-Host "[DEBUG-vb6] markers-alias: exit $($p.ExitCode); EXE $(Test-Path "$probe/Project1.exe")"
if (Test-Path "$probe/markers-alias.log") { Get-Content "$probe/markers-alias.log" }
$p = Start-Process "$env:SystemRoot/SysWOW64/regsvr32.exe" -ArgumentList '/s', 'msvbvm60.dll' -Wait -PassThru
Write-Host "[DEBUG-vb6] Runtime registration: exit $($p.ExitCode)"
$p = Start-Process $compiler -WorkingDirectory $projectDir -PassThru -ArgumentList (
    '/make Project1.vbp /out "{0}" /outdir "{1}"' -f "$probe/markers-runtime.log", $probe
)
if (!$p.WaitForExit(15000)) { $p.Kill($true); $p.WaitForExit() }
Write-Host "[DEBUG-vb6] markers-runtime: exit $($p.ExitCode); EXE $(Test-Path "$probe/Project1.exe")"
if (Test-Path "$probe/markers-runtime.log") { Get-Content "$probe/markers-runtime.log" }
Start-Sleep 3
Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$start} -ErrorAction SilentlyContinue |
    Where-Object Message -Match 'vb6|vba6|c2.exe' |
    Format-List TimeCreated, Id, Message | Out-String | Tee-Object "$probe/events.txt" | Write-Host

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$probe = Join-Path $root '.build/logs/vb6/probe'
New-Item -ItemType Directory -Force $probe | Out-Null
@'
VERSION 5.00
Begin VB.Form Form1
    Caption = "Probe"
End
Attribute VB_Name = "Form1"
Attribute VB_PredeclaredId = True
'@ | Set-Content -Encoding ascii "$probe/Form1.frm"
@'
Type=Exe
Form=Form1.frm
Startup="Form1"
ExeName32="Probe.exe"
Name="Probe"
CompilationType=0
'@ | Set-Content -Encoding ascii "$probe/Probe.vbp"
$compiler = "$root/.build/vb6/Vb6.exe"
function Probe([string]$Name) {
    $arguments = '/make Probe.vbp /out "{0}" /outdir "{1}"' -f "$probe/$Name.log", $probe
    $p = Start-Process $compiler -WorkingDirectory $probe -PassThru -ArgumentList $arguments
    if (!$p.WaitForExit(15000)) { $p.Kill($true); $p.WaitForExit() }
    Write-Host "[DEBUG-vb6] ${Name}: exit $($p.ExitCode); EXE $(Test-Path "$probe/Probe.exe")"
    if (Test-Path "$probe/$Name.log") { Get-Content "$probe/$Name.log" }
    if (Test-Path "$probe/Probe.exe") { Remove-Item "$probe/Probe.exe" }
}
Probe 'empty-form'
# Match the original installer ProductDir setting, independently of type library registration.
& "$env:SystemRoot/System32/reg.exe" add 'HKLM\SOFTWARE\Microsoft\VisualStudio\6.0\Setup\Microsoft Visual Basic' /v ProductDir /t REG_SZ /d "$root\.build\vb6" /f /reg:32
Probe 'empty-form-productdir'
# The source's built-in controls, with its event handlers omitted only in this temporary probe.
$form = Get-Content "$root/Examples/Code Markers/VB6/Form1.frm" -Raw
($form -split 'Private Sub Command1_Click')[0] | Set-Content -Encoding ascii "$probe/Form1.frm"
Probe 'sample-controls'

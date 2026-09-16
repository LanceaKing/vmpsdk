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
$form = Get-Content "$root/Examples/Code Markers/VB6/Form1.frm" -Raw
$lines = (($form -split 'Private Sub Command1_Click')[0] -split "`r?`n")
$structure = $lines | Where-Object { $_ -match '^\s*(VERSION|Begin |End\s*$|Attribute VB_Name)' }
$structure | Set-Content -Encoding ascii "$probe/Form1.frm"
Probe 'controls-only'
foreach ($control in @('CommandButton', 'TextBox', 'Label')) {
    @"
VERSION 5.00
Begin VB.Form Form1
    Begin VB.$control Control1
    End
End
Attribute VB_Name = "Form1"
Attribute VB_PredeclaredId = True
"@ | Set-Content -Encoding ascii "$probe/Form1.frm"
    Probe "only-$control"
}
# Test each nonstructural line in its original location, with all other values omitted.
foreach ($index in 0..($lines.Count - 1)) {
    $line = $lines[$index]
    if (!$line.Trim() -or $line -match '^\s*(VERSION|Begin |End\s*$|Attribute VB_Name)') { continue }
    $candidate = for ($i=0; $i -lt $lines.Count; $i++) {
        if ($i -eq $index -or $lines[$i] -match '^\s*(VERSION|Begin |End\s*$|Attribute VB_Name)') { $lines[$i] }
    }
    $candidate | Set-Content -Encoding ascii "$probe/Form1.frm"
    Write-Host "[DEBUG-vb6] Property: $line"
    Probe "property-$index"
}

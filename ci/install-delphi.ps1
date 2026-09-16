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
    # Use the file mirror directly; the download portal can return an HTML page.
    & curl.exe --fail --location --retry 3 --output $archive "https://phoenixnap.dl.sourceforge.net/project/c0de-s/$stem.rar"
    if ($LASTEXITCODE -ne 0) { throw "Delphi download failed with exit code $LASTEXITCODE" }
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
# The installer's CheckInstallForWin64Bit returns False in silent mode on x64.
# Drive its native wizard instead. Both downloaded files were SHA-256 checked;
# NoExeVerify skips the repack's timestamp/version-metadata check, not payload CRCs.
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class DelphiSetupWindow {
    public IntPtr Handle;
    public uint ProcessId;
    public string Class;
    public string Text;
    public bool Enabled;
}
public static class DelphiSetupUI {
    delegate bool EnumProc(IntPtr handle, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc callback, IntPtr data);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr handle);
    [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr handle);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr handle, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr handle, StringBuilder text, int size);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr handle, StringBuilder text, int size);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr handle, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr handle, uint message, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
    static DelphiSetupWindow Read(IntPtr handle) {
        uint pid;
        GetWindowThreadProcessId(handle, out pid);
        var text = new StringBuilder(4096);
        var cls = new StringBuilder(256);
        GetWindowText(handle, text, text.Capacity);
        GetClassName(handle, cls, cls.Capacity);
        return new DelphiSetupWindow { Handle = handle, ProcessId = pid, Class = cls.ToString(), Text = text.ToString(), Enabled = IsWindowEnabled(handle) };
    }
    public static DelphiSetupWindow[] Windows(IntPtr parent) {
        var windows = new List<DelphiSetupWindow>();
        EnumProc callback = (handle, data) => { if (IsWindowVisible(handle)) windows.Add(Read(handle)); return true; };
        if (parent == IntPtr.Zero) EnumWindows(callback, IntPtr.Zero);
        else EnumChildWindows(parent, callback, IntPtr.Zero);
        return windows.ToArray();
    }
    public static bool Checked(IntPtr handle) {
        IntPtr result;
        if (SendMessageTimeout(handle, 0xF0, IntPtr.Zero, IntPtr.Zero, 2, 1000, out result) == IntPtr.Zero)
            throw new Exception("Delphi installer control is unresponsive");
        return result.ToInt64() == 1;
    }
    public static void Click(IntPtr handle) {
        if (!PostMessage(handle, 0xF5, IntPtr.Zero, IntPtr.Zero)) throw new Exception("Cannot click Delphi installer control");
    }
}
'@
$arguments = '/SP- /NORESTART /NoExeVerify /TYPE=full /TASKS="" /LANG=en /DIR="{0}" /LOG="{1}"' -f $sdk, $installLog
$process = Start-Process $installer -ArgumentList $arguments -PassThru
try {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $lastStates = @{}
    $nextLogAt = 30
    while (!$process.WaitForExit(500)) {
        if ($timer.Elapsed.TotalMinutes -ge 10) { throw 'Delphi installation timed out after 10 minutes' }
        if ($timer.Elapsed.TotalSeconds -ge $nextLogAt) {
            if (Test-Path $installLog) { Get-Content $installLog -Tail 5 | Write-Host }
            $nextLogAt += 30
        }
        # Inno Setup runs the wizard in a renamed temporary child process.
        $processes = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId)
        $owners = @($process.Id)
        for ($index = 0; $index -lt $owners.Count; $index++) {
            $owners += @($processes | Where-Object { $_.ParentProcessId -eq $owners[$index] -and $_.ProcessId -notin $owners } | ForEach-Object ProcessId)
        }
        foreach ($window in [DelphiSetupUI]::Windows([IntPtr]::Zero)) {
            if ($window.ProcessId -notin $owners) { continue }
            if ($window.Class -in @('TApplication', 'TWindowDisabler-Window')) { continue }
            $controls = @([DelphiSetupUI]::Windows($window.Handle))
            $state = (@($window) + $controls | ForEach-Object { "$($_.Class): $($_.Text) [enabled=$($_.Enabled)]" }) -join "`n"
            if ($state -ne $lastStates[$window.Handle]) {
                Write-Host $state
                $lastStates[$window.Handle] = $state
            }
            $buttons = @($controls | Where-Object { $_.Enabled -and $_.Class -match 'Button$' })
            if ($window.Class -eq '#32770') {
                # Confirm only the installer's known warning about a 32-bit IDE on x64.
                if ($state -notmatch '(?i)64.bit') { throw "Unexpected Delphi installer dialog: $state" }
                $next = $buttons | Where-Object { $_.Text.Replace('&', '') -eq 'Yes' } | Select-Object -First 1
                if (!$next) { throw "Missing Yes button in Delphi x64 warning: $state" }
                [DelphiSetupUI]::Click($next.Handle)
                continue
            }
            if ($window.Class -ne 'TWizardForm') { continue }
            $accept = $controls | Where-Object { $_.Class -match 'RadioButton$' -and $_.Text.Replace('&', '') -match '^I accept' } | Select-Object -First 1
            if ($accept -and ![DelphiSetupUI]::Checked($accept.Handle)) {
                [DelphiSetupUI]::Click($accept.Handle)
                continue
            }
            # Do not launch the IDE or documentation after installing.
            $launch = $controls | Where-Object { $_.Class -match 'CheckBox$' -and $_.Text -match '(?i)launch|readme|run .*delphi' -and [DelphiSetupUI]::Checked($_.Handle) } | Select-Object -First 1
            if ($launch) {
                [DelphiSetupUI]::Click($launch.Handle)
                continue
            }
            $next = $buttons | Where-Object { $_.Text.Replace('&', '').Trim() -in @('Next >', 'I Agree >', 'Install', 'Finish') } | Select-Object -First 1
            if ($next) { [DelphiSetupUI]::Click($next.Handle) }
        }
    }
    if ($process.ExitCode -ne 0) { throw "Delphi installer exited with $($process.ExitCode)" }
    foreach ($file in @('Bin\dcc32.exe', 'Bin\brcc32.exe', 'Bin\rlink32.dll', 'Lib\System.dcu', 'Lib\Forms.dcu')) {
        $path = Join-Path $sdk $file
        if (!(Test-Path $path) -or (Get-Item $path).Length -eq 0) { throw "Missing Delphi toolchain file: $path" }
    }
} catch {
    if (!$process.HasExited) { $process.Kill($true); $process.WaitForExit() }
    if (Test-Path $installLog) { Get-Content $installLog -Tail 80 | Write-Host }
    throw
} finally { $process.Dispose() }
Write-Host "Delphi 7 ready: $sdk"

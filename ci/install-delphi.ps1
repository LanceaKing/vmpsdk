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
// The first eight IAccessible methods, in COM vtable order. This old Inno
// control implements these methods but not IDispatch or accDoDefaultAction.
[ComImport, Guid("618736E0-3C3D-11CF-810C-00AA00389B71"), InterfaceType(ComInterfaceType.InterfaceIsDual)]
public interface IDelphiAccessible {
    [return: MarshalAs(UnmanagedType.IDispatch)] object GetParent();
    int GetChildCount();
    [return: MarshalAs(UnmanagedType.IDispatch)] object GetChild([MarshalAs(UnmanagedType.Struct)] object child);
    [return: MarshalAs(UnmanagedType.BStr)] string GetName([MarshalAs(UnmanagedType.Struct)] object child);
    [return: MarshalAs(UnmanagedType.BStr)] string GetValue([MarshalAs(UnmanagedType.Struct)] object child);
    [return: MarshalAs(UnmanagedType.BStr)] string GetDescription([MarshalAs(UnmanagedType.Struct)] object child);
    [return: MarshalAs(UnmanagedType.Struct)] object GetRole([MarshalAs(UnmanagedType.Struct)] object child);
    [return: MarshalAs(UnmanagedType.Struct)] object GetState([MarshalAs(UnmanagedType.Struct)] object child);
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
    [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr handle);
    [DllImport("user32.dll")] static extern int GetDlgCtrlID(IntPtr handle);
    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SendMessageTimeout(IntPtr handle, uint message, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out UIntPtr result);
    [DllImport("oleacc.dll")] static extern int AccessibleObjectFromWindow(IntPtr handle, uint objectId, ref Guid iid, out IDelphiAccessible accessible);
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
    public static void PressButton(IntPtr handle) {
        // BN_CLICKED avoids BM_CLICK's dependence on the active desktop/dialog.
        if (!IsWindowEnabled(handle) || !PostMessage(GetParent(handle), 0x111, new IntPtr(GetDlgCtrlID(handle) & 0xFFFF), handle))
            throw new Exception("Cannot press Delphi installer button");
    }
    static long Send(IntPtr handle, uint message, int wParam, int lParam) {
        UIntPtr result;
        if (SendMessageTimeout(handle, message, new IntPtr(wParam), new IntPtr(lParam), 2, 5000, out result) == IntPtr.Zero)
            throw new Exception("Delphi installer checklist did not respond");
        return unchecked((long)result.ToUInt64());
    }
    public static int UncheckLaunch(IntPtr handle) {
        var iid = typeof(IDelphiAccessible).GUID;
        IDelphiAccessible accessible;
        Marshal.ThrowExceptionForHR(AccessibleObjectFromWindow(handle, 0xFFFFFFFC, ref iid, out accessible)); // OBJID_CLIENT
        try {
            int found = 0;
            for (int child = 1; child <= accessible.GetChildCount(); child++) {
                string name = accessible.GetName(child);
                if (name == null || !name.Replace("&", "").StartsWith("Launch Delphi 7 Lite Full Edition", StringComparison.Ordinal)) continue;
                found++;
                int state = Convert.ToInt32(accessible.GetState(child));
                if (Convert.ToInt32(accessible.GetRole(child)) != 0x2C || (state & 0x21) != 0)
                    throw new Exception("Unexpected launch checkbox role/state: " + state);
                Console.WriteLine("Delphi launch checkbox: " + name + "; checked=" + ((state & 0x10) != 0));
                if ((state & 0x10) != 0) {
                    // LB_SETCURSEL selects the item; Space changes its checked state.
                    // Synchronous messages let us read back the result before Finish.
                    Send(handle, 0x186, child - 1, 0);
                    if (Send(handle, 0x188, 0, 0) != child - 1)
                        throw new Exception("Cannot select Delphi launch checkbox");
                    Send(handle, 0x100, 0x20, 1); // WM_KEYDOWN / VK_SPACE
                    Send(handle, 0x101, 0x20, unchecked((int)0xC0000001)); // WM_KEYUP
                }
                if ((Convert.ToInt32(accessible.GetState(child)) & 0x30) != 0)
                    throw new Exception("Delphi launch checkbox is still checked");
                Console.WriteLine("Verified Delphi launch checkbox is unchecked before Finish");
            }
            return found;
        } finally { Marshal.ReleaseComObject(accessible); }
    }
}
'@
$arguments = '/SP- /NORESTART /NoExeVerify /TYPE=full /TASKS="" /LANG=en /DIR="{0}" /LOG="{1}"' -f $sdk, $installLog
$process = Start-Process $installer -ArgumentList $arguments -PassThru
try {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $lastStates = @{}
    $launchUnchecked = $false
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
                [DelphiSetupUI]::PressButton($next.Handle)
                continue
            }
            if ($window.Class -ne 'TWizardForm') { continue }
            $next = $buttons | Where-Object { $_.Text.Replace('&', '').Trim() -in @('Next >', 'I Agree >', 'Install', 'Finish') } | Select-Object -First 1
            if ($next) {
                if ($next.Text.Replace('&', '').Trim() -eq 'Finish') {
                    $found = 0
                    foreach ($list in @($controls | Where-Object { $_.Enabled -and $_.Class -eq 'TNewCheckListBox' })) {
                        $found += [DelphiSetupUI]::UncheckLaunch($list.Handle)
                    }
                    if ($found -ne 1) { throw "Expected one Delphi launch checkbox on the finish page, found $found" }
                    $launchUnchecked = $true
                }
                [DelphiSetupUI]::PressButton($next.Handle)
            }
        }
    }
    if ($process.ExitCode -ne 0) { throw "Delphi installer exited with $($process.ExitCode)" }
    if (!$launchUnchecked) { throw 'Delphi installer exited without verifying the launch checkbox' }
    if (Get-Process -Name delphi32 -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq (Join-Path $sdk 'Bin\delphi32.exe') }) {
        throw 'Delphi IDE unexpectedly started after installation'
    }
    Write-Host 'Verified the installed Delphi IDE is not running'
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

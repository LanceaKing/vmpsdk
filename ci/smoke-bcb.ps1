$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class BcbWindows {
    public class Window {
        public IntPtr Handle;
        public string Class, Text;
        public bool Visible;
        public override string ToString() { return $"HWND={Handle}, class={Class}, visible={Visible}, text={Text}"; }
    }
    delegate bool EnumProc(IntPtr handle, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc callback, IntPtr data);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr handle, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr handle);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr handle, StringBuilder text, int size);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr SendMessageTimeout(IntPtr handle, uint message, UIntPtr wParam, StringBuilder text, uint flags, uint timeout, out UIntPtr result);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool PostMessage(IntPtr handle, uint message, IntPtr wParam, IntPtr lParam);
    static Window Read(IntPtr handle) {
        var cls = new StringBuilder(256);
        var text = new StringBuilder(2048);
        GetClassName(handle, cls, cls.Capacity);
        UIntPtr result;
        SendMessageTimeout(handle, 0x000D, new UIntPtr((uint)text.Capacity), text, 2, 500, out result);
        return new Window { Handle=handle, Class=cls.ToString(), Text=text.ToString(), Visible=IsWindowVisible(handle) };
    }
    public static Window[] Snapshot(uint processId, bool children) {
        var windows = new List<Window>();
        EnumWindows((handle, data) => {
            uint pid;
            GetWindowThreadProcessId(handle, out pid);
            if (pid != processId) return true;
            windows.Add(Read(handle));
            if (children) EnumChildWindows(handle, (child, state) => { windows.Add(Read(child)); return true; }, IntPtr.Zero);
            return true;
        }, IntPtr.Zero);
        return windows.ToArray();
    }
}
'@
foreach ($example in @(
    @{Folder='markers-bcb-x86'; Exe='Project1.exe'; Title='VMProtect test [Borland C++ Builder]'},
    @{Folder='licensing-bcb-x86'; Exe='TestApp.exe'; Title='License Test App'}
)) {
    $folder = "$root\.build\artifacts\$($example.Folder)"
    $exe = Join-Path $folder $example.Exe
    # Launch only the freshly built executable with its packaged runtime beside it.
    $process = Start-Process $exe -WorkingDirectory $folder -PassThru
    try {
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while ($true) {
            if ($process.WaitForExit(200)) {
                throw "$($example.Exe) exited before showing its form: $($process.ExitCode)"
            }
            $forms = @([BcbWindows]::Snapshot($process.Id, $false) | Where-Object {
                $_.Visible -and $_.Class -ceq 'TForm1' -and $_.Text -ceq $example.Title
            })
            if ($forms.Count -eq 1) { break }
            if ($timer.Elapsed.TotalSeconds -ge 15) {
                [BcbWindows]::Snapshot($process.Id, $true) | ForEach-Object { Write-Host $_ }
                throw "$($example.Exe) did not show its form; PID=$($process.Id)"
            }
        }
        Write-Host "PASS: $($example.Exe): PID=$($process.Id), $($forms[0])"
        if (![BcbWindows]::PostMessage($forms[0].Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) -or !$process.WaitForExit(5000)) {
            throw "$($example.Exe) did not close its form normally"
        }
        if ($process.ExitCode -ne 0) { throw "$($example.Exe) exited with $($process.ExitCode)" }
        Write-Host "PASS: $($example.Exe) closed normally with exit code 0"
    } finally {
        if (!$process.HasExited) { $process.Kill($true) }
        $process.Dispose()
    }
}

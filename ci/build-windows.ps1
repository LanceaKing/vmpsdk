param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('native', 'masm', 'vb6', 'managed', 'pascal')][string]$Kind,
    [ValidateSet('x86', 'x64')][string]$Arch = 'x86'
)
$ErrorActionPreference = 'Stop'
if ($Kind -eq 'masm' -and $Arch -ne 'x86') { throw 'The MASM example supports only x86' }
if ($Kind -eq 'vb6' -and $Arch -ne 'x86') { throw 'The VB6 examples support only x86' }
$root = Split-Path $PSScriptRoot -Parent
$work = Join-Path $root '.build/work'
$out = Join-Path $root '.build/artifacts'
function Run([string]$Tool, [string[]]$Arguments) {
    & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Tool exited with $LASTEXITCODE" }
}
function Directory([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    return $Path
}
if ($Kind -in @('native', 'managed')) {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $vs = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -property installationPath
    if (!$vs) { throw 'Visual Studio not found' }
    Import-Module "$vs\Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
    Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation -DevCmdArguments "-arch=$Arch -host_arch=x64"
}
if ($Kind -eq 'native') {
    $bits = if ($Arch -eq 'x64') { '64' } else { '32' }
    foreach ($example in @(
        @{Folder='Code Markers'; Name='Project1'; Resource='Resource.rc'; Artifact='markers'},
        @{Folder='Licensing'; Name='TestApp'; Resource='TestApp.rc'; Artifact='licensing'}
    )) {
        Push-Location "$work\Examples\$($example.Folder)\MSVC"
        try {
            $dest = Directory "$out\$($example.Artifact)-$Arch"
            if ($Arch -eq 'x86') {
                # Build the original vcxproj; retarget only through global properties.
                Run 'msbuild' @("$($example.Name).vcxproj", '/m', '/t:Build', '/p:Configuration=Release',
                    '/p:Platform=Win32', '/p:PlatformToolset=v143', '/p:WindowsTargetPlatformVersion=10.0',
                    "/p:OutDir=$dest\", "/p:IntDir=$root\.build\obj\$($example.Artifact)\")
            } else {
                # The original vcxproj declares only Win32. Use its sources directly for x64.
                Run 'rc' @('/nologo', "/fo$dest\Resources.res", $example.Resource)
                $defines = @('/DWIN32', '/DNDEBUG', '/D_WINDOWS')
                if ($example.Folder -eq 'Licensing') { $defines += @('/DUNICODE', '/D_UNICODE') }
                Run 'cl' (@('/nologo', '/O2', '/MT', '/EHsc', '/D_CRT_SECURE_NO_WARNINGS') + $defines +
                    @("$($example.Name).cpp", 'stdafx.cpp', "$dest\Resources.res", "/Fe$dest\$($example.Name).exe",
                      '/link', '/SUBSYSTEM:WINDOWS', 'user32.lib', "/LIBPATH:$work\Lib\Windows"))
            }
            Copy-Item "$work\Lib\Windows\VMProtectSDK$bits.dll" $dest
            if (!(Test-Path "$dest\$($example.Name).exe")) { throw 'Missing native executable' }
        } finally { Pop-Location }
    }
    # Modern MSBuild cannot open VS2008 vcproj files. Compile the listed source files
    # and resource with the original definitions, without converting the projects.
    $dest = Directory "$out\keygen-$Arch"
    Push-Location "$work\Examples\KeyGen\DLL\Sources"
    try {
        Run 'rc' @('/nologo', "/fo$dest\KeyGen.res", 'KeyGen.rc')
        # Old STL headers supplied <string> transitively; inject it via /FI on modern MSVC.
        Run 'cl' @('/nologo', '/O2', '/MT', '/EHsc', '/FIstring', '/LD', '/DWIN32', '/DNDEBUG', '/D_WINDOWS',
            '/D_USRDLL', '/DKEYGEN_EXPORTS', '/DUNICODE', '/D_UNICODE', '/D_CRT_SECURE_NO_WARNINGS',
            'KeyGen.cpp', 'b64.cpp', 'sha-1.cpp', 'sshbn.cpp', 'stdafx.cpp', "$dest\KeyGen.res",
            "/Fe$dest\KeyGen$bits.dll", '/link', '/DEF:KeyGen.def', "/IMPLIB:$dest\KeyGen$bits.lib")
    } finally { Pop-Location }
    Push-Location "$work\Examples\KeyGen\DLL\MSVC"
    try {
        Run 'cl' @('/nologo', '/O2', '/MT', '/EHsc', '/DUNICODE', '/D_UNICODE',
            'KeyGenExample.cpp', 'stdafx.cpp', "/Fe$dest\KeyGenExample.exe", '/link', "/LIBPATH:$dest")
        # The untouched sample intentionally has no product key data.
        Run "$dest\KeyGenExample.exe" @()
    } finally { Pop-Location }
} elseif ($Kind -eq 'masm') {
    # The original includes use drive-rooted paths: \masm32 must be on the work drive.
    $sdk = Join-Path ([IO.Path]::GetPathRoot($work)) 'masm32'
    $dest = Directory "$out\masm-x86"
    Push-Location "$work\Examples\Code Markers\MASM"
    try {
        # Same assembler/linker and options as makeit.bat, without its final pause.
        # This example uses in-memory dialogs and has no rsrc.rc.
        Run "$sdk\bin\ml.exe" @('/c', '/coff', 'Project1.asm')
        Run "$sdk\bin\link.exe" @('/SUBSYSTEM:WINDOWS', 'Project1.obj', "/OUT:$dest\Project1.exe")
        if (!(Test-Path "$dest\Project1.exe")) { throw 'Missing MASM executable' }
        Copy-Item 'VMProtectSDK32.dll' $dest
    } finally { Pop-Location }
} elseif ($Kind -eq 'vb6') {
    $compiler = "$root\.build\vb6\Vb6.exe"
    if (!(Test-Path $compiler)) { throw 'VB6 compiler missing; run ci/install-vb6.ps1 first' }
    $logs = Directory "$root\.build\logs\vb6"
    foreach ($example in @(
        @{Folder='Code Markers'; Name='Project1'; Artifact='markers-vb6-x86'},
        @{Folder='Licensing'; Name='TestApp'; Artifact='licensing-vb6-x86'}
    )) {
        $projectDir = "$work\Examples\$($example.Folder)\VB6"
        $dest = Directory "$out\$($example.Artifact)"
        $exe = "$dest\$($example.Name).exe"
        $log = "$logs\$($example.Name).log"
        # A stale executable must never turn a failed compilation into a pass.
        if (Test-Path $exe) { throw "Refusing to overwrite existing VB6 executable: $exe" }
        if (Test-Path $log) { Remove-Item $log }
        $arguments = '/make {0}.vbp /out "{1}" /outdir "{2}"' -f $example.Name, $log, $dest
        Write-Host "VB6 arguments: $arguments"
        $process = Start-Process $compiler -WorkingDirectory $projectDir -PassThru -ArgumentList $arguments
        try {
            if (!$process.WaitForExit(120000)) {
                $process.Kill($true)
                $process.WaitForExit()
                throw "VB6 compilation timed out: $($example.Name)"
            }
            if ($process.ExitCode -ne 0) { throw "VB6 exited with $($process.ExitCode): $($example.Name)" }
            # VB6 can return zero after a build error. Require the success log and EXE.
            if (!(Test-Path $log) -or (Get-Content $log -Raw) -notmatch 'Build of .* succeeded') {
                throw "VB6 did not report a successful build: $($example.Name)"
            }
            if (!(Test-Path $exe) -or (Get-Item $exe).Length -eq 0) {
                throw "Missing VB6 executable: $exe"
            }
            Copy-Item "$work\Lib\Windows\VMProtectSDK32.dll" $dest
        } finally {
            if (Test-Path $log) { Get-Content $log | Write-Host }
            $process.Dispose()
        }
    }
} elseif ($Kind -eq 'managed') {
    $packages = Directory "$root\.build\packages"
    foreach ($framework in @('net20', 'net40')) {
        Run 'nuget' @('install', "Microsoft.NETFramework.ReferenceAssemblies.$framework", '-Version', '1.0.3',
            '-OutputDirectory', $packages, '-NonInteractive', '-Source', 'https://api.nuget.org/v3/index.json')
    }
    foreach ($example in @(
        @{Project='Code Markers\Net\Project1.csproj'; Framework='net40'; Name='markers-net'},
        @{Project='Licensing\Net\TestApp.csproj'; Framework='net20'; Name='licensing-net'},
        @{Project='KeyGen\Net\KeyGen\KeyGen.csproj'; Framework='net20'; Name='keygen-net'},
        @{Project='KeyGen\Net\Usage\Usage.csproj'; Framework='net20'; Name='keygen-net'}
    )) {
        $dest = Directory "$out\$($example.Name)"
        $refs = "$packages\Microsoft.NETFramework.ReferenceAssemblies.$($example.Framework).1.0.3\build\"
        $project = "$work\Examples\$($example.Project)"
        $referencePath = if ($example.Name -eq 'keygen-net') { $dest } else { "$work\Lib\Windows\Net" }
        # ReferencePath supplies missing legacy HintPaths without editing the csproj.
        Run 'msbuild' @($project, '/m', '/t:Build', '/p:Configuration=Release',
            "/p:TargetFrameworkRootPath=$refs", "/p:OutDir=$dest\",
            "/p:ReferencePath=$referencePath",
            '/p:GenerateResourceMSBuildRuntime=CurrentRuntime', '/p:GenerateResourceMSBuildArchitecture=CurrentArchitecture')
    }
} elseif ($Kind -eq 'pascal') {
    $lazarus = 'C:\lazarus'
    $fpcbin = "$lazarus\fpc\3.2.2\bin\i386-win32"
    if (!(Test-Path "$fpcbin\fpc.exe")) { throw 'Lazarus 4.0 with FPC 3.2.2 (Win32) is required' }
    $dest = Directory "$out\fpc-x86"
    Push-Location "$work\Examples\Code Markers\Free Pascal"
    try {
        # Same compile and strip options as makeit.bat; only the compiler location differs.
        Run "$fpcbin\fpc.exe" @('-TWin32', '-Sd', '-WG', 'Project1.pas')
        Run "$fpcbin\strip.exe" @('Project1.exe')
        Copy-Item Project1.exe, VMProtectSDK32.dll $dest
    } finally { Pop-Location }
    $dest = Directory "$out\lazarus-x86"
    Push-Location "$work\Examples\Code Markers\Lazarus"
    try {
        # Invoke FPC with Lazarus' precompiled LCL units to avoid lpi auto-upgrades.
        Run "$fpcbin\fpc.exe" @('-TWin32', '-Sd', '-WG',
            "-Fu$lazarus\lcl\units\i386-win32", "-Fu$lazarus\lcl\units\i386-win32\win32",
            "-Fu$lazarus\components\lazutils\lib\i386-win32", "-Fu$lazarus\packager\units\i386-win32",
            'project1.lpr')
        Copy-Item project1.exe, VMProtectSDK32.dll $dest
    } finally { Pop-Location }
}

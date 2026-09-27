# Builds VimEdit, bundles the Qt runtime next to the exe (windeployqt), and
# wraps it in an Inno Setup installer:
#   dist\VimEdit-<version>-windows-x64-setup.exe
#
# Needs Visual Studio (or its Build Tools) with the C++ workload, Qt's bin
# directory on PATH, and Inno Setup 6.
$ErrorActionPreference = "Stop"

# Load the MSVC build environment unless we're already in a Developer shell.
if (-not $env:VCToolsRedistDir) {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs) { throw "Visual Studio with the C++ workload not found" }
    & "$vs\Common7\Tools\Launch-VsDevShell.ps1" -Arch amd64 -HostArch amd64 -SkipAutomaticLocation | Out-Null
}

$root = Resolve-Path "$PSScriptRoot\.."
$version = (cargo metadata --no-deps --format-version 1 --manifest-path "$root\Cargo.toml" |
    ConvertFrom-Json).packages[0].version
$stage = "$root\target\release\deploy"
$dist = "$root\dist"

cargo build --release --manifest-path "$root\Cargo.toml"
if ($LASTEXITCODE) { throw "cargo build failed" }

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory $stage | Out-Null
Copy-Item "$root\target\release\vim-edit.exe" $stage

windeployqt --release --qmldir "$root\qml" --no-compiler-runtime --no-opengl-sw "$stage\vim-edit.exe"
if ($LASTEXITCODE) { throw "windeployqt failed" }

# Ship the MSVC runtime DLLs app-locally so a fresh Windows install doesn't
# need the Visual C++ Redistributable.
Copy-Item "$env:VCToolsRedistDir\x64\Microsoft.VC*.CRT\*.dll" $stage

$iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
& $iscc "/DAppVersion=$version" "/DSourceDir=$stage" "/DOutputDir=$dist" "$root\packaging\windows\installer.iss"
if ($LASTEXITCODE) { throw "ISCC failed" }

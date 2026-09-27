# Builds VimEdit, bundles the Qt runtime next to the exe (windeployqt), and
# wraps it in an Inno Setup installer:
#   dist\VimEdit-<version>-windows-x64-setup.exe
#
# Run from a "Developer PowerShell for VS" (it needs VCToolsRedistDir) with
# Qt's bin directory on PATH and Inno Setup 6 installed.
$ErrorActionPreference = "Stop"

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
if (-not $env:VCToolsRedistDir) { throw "VCToolsRedistDir not set; run from a Developer PowerShell" }
Copy-Item "$env:VCToolsRedistDir\x64\Microsoft.VC*.CRT\*.dll" $stage

$iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
& $iscc "/DAppVersion=$version" "/DSourceDir=$stage" "/DOutputDir=$dist" "$root\packaging\windows\installer.iss"
if ($LASTEXITCODE) { throw "ISCC failed" }

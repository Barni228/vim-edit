# Registers vim-edit.exe (per user, no admin needed) so it shows up in
# Explorer's "Open with" menu for .txt files. Windows passes the file path
# as the first command-line argument.
#
#   powershell -ExecutionPolicy Bypass -File packaging\windows\register-file-association.ps1
#   powershell -ExecutionPolicy Bypass -File packaging\windows\register-file-association.ps1 -Unregister
param(
    [string]$ExePath = (Join-Path $PSScriptRoot "..\..\target\release\vim-edit.exe"),
    [switch]$Unregister
)

$ErrorActionPreference = "Stop"
$classes = "HKCU:\Software\Classes"
$progId = "VimEdit.txt"
$appKey = "$classes\Applications\vim-edit.exe"

function Set-Key([string]$Path, [string]$Name, [string]$Value) {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value
}

if ($Unregister) {
    Remove-Item "$classes\$progId" -Recurse -ErrorAction SilentlyContinue
    Remove-Item $appKey -Recurse -ErrorAction SilentlyContinue
    Remove-ItemProperty "$classes\.txt\OpenWithProgids" -Name $progId -ErrorAction SilentlyContinue
} else {
    $exe = (Resolve-Path $ExePath).Path
    $command = "`"$exe`" `"%1`""

    Set-Key "$classes\$progId" "(default)" "Text Document"
    Set-Key "$classes\$progId\DefaultIcon" "(default)" "`"$exe`",0"
    Set-Key "$classes\$progId\shell\open\command" "(default)" $command
    Set-Key "$classes\.txt\OpenWithProgids" $progId ""

    Set-Key $appKey "FriendlyAppName" "VimEdit"
    Set-Key "$appKey\shell\open\command" "(default)" $command
    Set-Key "$appKey\SupportedTypes" ".txt" ""
}

# Tell Explorer that file associations changed.
Add-Type -Namespace Win32 -Name Shell -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("shell32.dll")]
public static extern void SHChangeNotify(int eventId, uint flags, System.IntPtr item1, System.IntPtr item2);
"@
[Win32.Shell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)

if ($Unregister) { "Unregistered VimEdit" } else { "Registered $exe for .txt" }

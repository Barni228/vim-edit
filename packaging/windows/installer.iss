; Inno Setup script for the VimEdit Windows installer.
; Built by scripts/package-windows.ps1, which passes AppVersion, SourceDir
; (the windeployqt output) and OutputDir on the command line.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppExe "vim-edit.exe"

[Setup]
AppId={{60400077-1FA8-4F67-BBE6-39DDCA812F3D}
AppName=VimEdit
AppVersion={#AppVersion}
AppVerName=VimEdit {#AppVersion}
AppPublisher=Barni228
AppPublisherURL=https://github.com/Barni228/vim-edit
DefaultDirName={autopf}\VimEdit
DefaultGroupName=VimEdit
DisableProgramGroupPage=yes
; Install per user without admin rights; the wizard offers an all-users install.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
ChangesAssociations=yes
UninstallDisplayIcon={app}\{#AppExe}
OutputDir={#OutputDir}
OutputBaseFilename=VimEdit-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\VimEdit"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\VimEdit"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

; "Open with" registration for .txt files. HKA is HKCU for per-user installs
; and HKLM for all-users installs.
[Registry]
Root: HKA; Subkey: "Software\Classes\VimEdit.txt"; ValueType: string; ValueName: ""; ValueData: "Text Document"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\VimEdit.txt\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""
Root: HKA; Subkey: "Software\Classes\.txt\OpenWithProgids"; ValueType: string; ValueName: "VimEdit.txt"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "VimEdit"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".txt"; ValueData: ""

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,VimEdit}"; Flags: nowait postinstall skipifsilent

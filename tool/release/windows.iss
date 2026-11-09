; Inno Setup 6+; compiler supplied via ISCC_PATH. See jrsoftware.org/ishelp/.
[Setup]
AppId={{FBE27513-5C82-4C7F-A8E5-55C2101BC80B}
AppName=mmx Studio
AppVersion={#Version}
DefaultDirName={localappdata}\Programs\mmx
DefaultGroupName=mmx Studio
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\studio\mmx_studio.exe
OutputDir={#Output}
#ifdef Signed
OutputBaseFilename=mmx-{#Version}-windows-signed
SignTool=mmx
SignedUninstaller=yes
#else
OutputBaseFilename=mmx-{#Version}-windows-unsigned
#endif
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
LicenseFile={#Stage}\LICENSE
SetupLogging=yes

[Files]
Source: "{#Stage}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\mmx Studio"; Filename: "{app}\studio\mmx_studio.exe"
Name: "{group}\Uninstall mmx Studio"; Filename: "{uninstallexe}"

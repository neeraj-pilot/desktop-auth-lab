param(
    [Parameter(Mandatory = $true)]
    [string] $SourceDir,

    [Parameter(Mandatory = $true)]
    [string] $InstallerPath
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
    throw "Source directory not found: $SourceDir"
}

$sourceRoot = (Resolve-Path -LiteralPath $SourceDir).Path
$installerFullPath = [System.IO.Path]::GetFullPath($InstallerPath)
$installerDir = Split-Path -Parent $installerFullPath
$outputBaseFilename = [System.IO.Path]::GetFileNameWithoutExtension($installerFullPath)

New-Item -ItemType Directory -Force -Path $installerDir | Out-Null
Remove-Item -LiteralPath $installerFullPath -Force -ErrorAction SilentlyContinue

$pubspecPath = Join-Path $PSScriptRoot "..\pubspec.yaml"
$versionLine = Select-String -LiteralPath $pubspecPath -Pattern "^version:\s*(\S+)" | Select-Object -First 1
if (-not $versionLine) {
    throw "Could not read version from $pubspecPath"
}
$appVersion = $versionLine.Matches[0].Groups[1].Value

$iconPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\windows\runner\resources\app_icon.ico"))
$sourceGlob = (Join-Path $sourceRoot "*").Replace("/", "\")
$escapedInstallerDir = $installerDir.Replace("/", "\")
$issPath = Join-Path ([System.IO.Path]::GetTempPath()) "desktop-auth-lab-installer.iss"

$iss = @"
[Setup]
AppId=7C83A490-09EF-48BE-8A7D-09BFF29F10AC
AppVersion=$appVersion
AppName=Desktop Auth Lab
AppPublisher=Ente
AppPublisherURL=https://github.com/neeraj-pilot/desktop-auth-lab
AppSupportURL=https://github.com/neeraj-pilot/desktop-auth-lab
AppUpdatesURL=https://github.com/neeraj-pilot/desktop-auth-lab
DefaultDirName={autopf}\Desktop Auth Lab
DisableProgramGroupPage=yes
OutputDir=$escapedInstallerDir
OutputBaseFilename=$outputBaseFilename
Compression=zip
SolidCompression=yes
SetupIconFile=$iconPath
WizardStyle=modern
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\desktop_auth_lab.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "$sourceGlob"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Desktop Auth Lab"; Filename: "{app}\desktop_auth_lab.exe"
Name: "{autodesktop}\Desktop Auth Lab"; Filename: "{app}\desktop_auth_lab.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\desktop_auth_lab.exe"; Description: "{cm:LaunchProgram,Desktop Auth Lab}"; Flags: runascurrentuser nowait postinstall skipifsilent
"@

$utf8WithBom = [System.Text.UTF8Encoding]::new($true)
[System.IO.File]::WriteAllText($issPath, $iss, $utf8WithBom)

$iscc = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if (-not (Test-Path -LiteralPath $iscc -PathType Leaf)) {
    $isccCommand = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
    if (-not $isccCommand) {
        throw "Inno Setup compiler not found. Install Inno Setup 6 before running this script."
    }
    $iscc = $isccCommand.Source
}

& $iscc $issPath
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path -LiteralPath $installerFullPath -PathType Leaf)) {
    throw "Expected installer was not created: $installerFullPath"
}

Remove-Item -LiteralPath $issPath -Force -ErrorAction SilentlyContinue
Write-Host "Created installer: $installerFullPath"

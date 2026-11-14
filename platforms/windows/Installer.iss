[Setup]
AppId={{49B63264-3401-4BC6-97B5-0E44F411DD10}
AppName=簡繁注音
AppVersion=0.3.0
AppVerName=簡繁注音 0.3.0
AppPublisher=Jianfan Zhuyin contributors
AppPublisherURL=https://github.com/AllenPeng0209/jianfan-zhuyin
AppSupportURL=https://github.com/AllenPeng0209/jianfan-zhuyin/issues
DefaultDirName={autopf}\JianfanZhuyin
DefaultGroupName=簡繁注音
SourceDir=..\..
OutputDir=dist
OutputBaseFilename=JianfanZhuyin-0.3.0-windows-x64
SetupIconFile=platforms\windows\Resources\Jianfan.ico
UninstallDisplayIcon={app}\JianfanSettings.exe
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0.22000
PrivilegesRequired=admin
CloseApplications=no
RestartApplications=no
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
LicenseFile=LICENSE

[Languages]
Name: "chinesetraditional"; MessagesFile: "platforms\windows\InstallerLanguages\ChineseTraditional.isl"
Name: "chinesesimplified"; MessagesFile: "platforms\windows\InstallerLanguages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "dist\windows-stage\x64\JianfanIME.dll"; DestDir: "{app}\x64"; Flags: ignoreversion restartreplace uninsrestartdelete
Source: "dist\windows-stage\x86\JianfanIME.dll"; DestDir: "{app}\x86"; Flags: ignoreversion restartreplace uninsrestartdelete
Source: "dist\windows-stage\x64\JianfanSettings.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\windows-stage\Data\*"; DestDir: "{app}\Data"; Flags: ignoreversion recursesubdirs
Source: "dist\windows-stage\ThirdPartyNotices.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\windows-stage\README-Windows.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\簡繁注音詞庫管理"; Filename: "{app}\JianfanSettings.exe"

[Run]
Filename: "{app}\JianfanSettings.exe"; Parameters: "--enable"; Flags: runhidden runasoriginaluser waituntilterminated

[UninstallRun]
Filename: "{app}\JianfanSettings.exe"; Parameters: "--disable"; Flags: runhidden waituntilterminated; RunOnceId: "DisableProfile"
Filename: "{sys}\regsvr32.exe"; Parameters: "/u /s ""{app}\x64\JianfanIME.dll"""; Flags: runhidden waituntilterminated; RunOnceId: "Unregister64"
Filename: "{syswow64}\regsvr32.exe"; Parameters: "/u /s ""{app}\x86\JianfanIME.dll"""; Flags: runhidden waituntilterminated; RunOnceId: "Unregister32"

[Code]
procedure RegisterIME(const ProgramPath, DLLPath: String);
var Code: Integer;
begin
  if not Exec(ProgramPath, '/s "' + DLLPath + '"', '', SW_HIDE, ewWaitUntilTerminated, Code) or (Code <> 0) then
    RaiseException('無法註冊簡繁注音，請重新執行安裝程式。');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    RegisterIME(ExpandConstant('{sys}\regsvr32.exe'), ExpandConstant('{app}\x64\JianfanIME.dll'));
    RegisterIME(ExpandConstant('{syswow64}\regsvr32.exe'), ExpandConstant('{app}\x86\JianfanIME.dll'));
  end;
end;

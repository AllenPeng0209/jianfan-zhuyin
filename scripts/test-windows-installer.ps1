$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
$classId = '{49B63264-3401-4BC6-97B5-0E44F411DD10}'
$userData = Join-Path $env:LOCALAPPDATA 'JianfanZhuyin'
foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
    $registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::ClassesRoot, $view)
    $existing = $registry.OpenSubKey("CLSID\$classId")
    if ($existing) { $existing.Dispose(); $registry.Dispose(); throw 'Installer tests require a disposable Windows environment without Jianfan installed.' }
    $registry.Dispose()
}
if (Test-Path $userData) { throw 'Existing personal data found. Run installer tests in a disposable Windows environment.' }
$installer = (Get-ChildItem dist/JianfanZhuyin-*-windows-x64.exe | Select-Object -First 1).FullName
if (-not $installer) { throw 'Build the Windows installer first.' }
$folder = Join-Path $env:ProgramFiles ('JianfanSmoke-' + [guid]::NewGuid().ToString())
$logs = Join-Path $PWD 'build/installer-smoke'
New-Item -ItemType Directory -Force $logs | Out-Null
$before = (Get-WinDefaultInputMethodOverride).InputMethodTip
$installed = $false
try {
    $setup = Start-Process -FilePath $installer -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$folder`"", "/LOG=`"$logs/install.log`"") -Wait -PassThru
    if ($setup.ExitCode -ne 0) { throw "Installer failed: $($setup.ExitCode)" }
    $installed = $true
    foreach ($arch in @('x64', 'x86')) {
        if (-not (Test-Path "$folder/$arch/JianfanIME.dll")) { throw "Missing $arch input service" }
    }
    if (-not (Test-Path "$folder/Data/data.txt")) { throw 'Bundled dictionary missing' }
    foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
        $registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::ClassesRoot, $view)
        $key = $registry.OpenSubKey("CLSID\$classId\InprocServer32")
        if (-not $key) { throw "Input service was not registered: $view" }
        if (-not $key.GetValue('').StartsWith($folder)) { throw 'Unexpected registration path' }
        $key.Dispose(); $registry.Dispose()
    }
    $after = (Get-WinDefaultInputMethodOverride).InputMethodTip
    if ($before -ne $after) { throw 'Installer changed the default input override' }
    New-Item -ItemType Directory -Force $userData | Out-Null
    $sentinel = Join-Path $userData 'installer-smoke-preserve.txt'
    [System.IO.File]::WriteAllText($sentinel, 'Test-only file: uninstall must preserve local user data.')
    $uninstall = Start-Process -FilePath "$folder/unins000.exe" -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=`"$logs/uninstall.log`"") -Wait -PassThru
    if ($uninstall.ExitCode -ne 0) { throw "Uninstall failed: $($uninstall.ExitCode)" }
    $installed = $false
    if (-not (Test-Path $sentinel)) { throw 'Uninstaller removed personal data' }
    Remove-Item -LiteralPath $sentinel
    foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
        $registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::ClassesRoot, $view)
        $key = $registry.OpenSubKey("CLSID\$classId")
        if ($key) { $key.Dispose(); throw 'Uninstaller left a registered input service' }
        $registry.Dispose()
    }
    'Installer registered both architectures, preserved the default override and retained user data on uninstall.'
} finally {
    if ($installed -and (Test-Path "$folder/unins000.exe")) {
        Start-Process -FilePath "$folder/unins000.exe" -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -Wait
    }
}

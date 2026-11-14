$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
$directory = Join-Path $PWD 'build/Windows/platforms/windows/Release'
$dll = Join-Path $directory 'JianfanIMETest.dll'
$registrar = Join-Path $env:WINDIR 'System32/regsvr32.exe'
try {
    # Register in a separate process, matching the actual installer workflow.
    $registered = Start-Process $registrar -ArgumentList @('/s', "`"$dll`"") -Wait -PassThru
    if ($registered.ExitCode -ne 0) { throw "Private TSF registration failed: $($registered.ExitCode)" }
    $enabled = Start-Process (Join-Path $directory 'JianfanSettingsTest.exe') -ArgumentList '--enable' -Wait -PassThru
    if ($enabled.ExitCode -ne 0) { throw 'Private TSF profile could not be enabled' }
    $test = Start-Process (Join-Path $directory 'WindowsCOMTest.exe') -Wait -PassThru
    Get-Content windows-com.log
    Get-Content windows-com-error.log
    if ($test.ExitCode -ne 0) { throw "Native input test failed: $($test.ExitCode)" }
} finally {
    Start-Process (Join-Path $directory 'JianfanSettingsTest.exe') -ArgumentList '--disable' -Wait
    Start-Process $registrar -ArgumentList @('/u', '/s', "`"$dll`"") -Wait
}

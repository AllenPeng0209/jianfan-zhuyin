$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
python scripts/generate-data.py
if ($LASTEXITCODE -ne 0) { throw 'Dictionary generation failed' }
foreach ($architecture in @('x64', 'Win32')) {
    $folder = "build/WindowsRelease-$architecture"
    cmake -S . -B $folder -A $architecture -DJIANFAN_TESTS=OFF
    if ($LASTEXITCODE -ne 0) { throw "CMake configuration failed: $architecture" }
    cmake --build $folder --config Release --target JianfanIME JianfanSettings --parallel 4
    if ($LASTEXITCODE -ne 0) { throw "Release build failed: $architecture" }
    $label = if ($architecture -eq 'Win32') { 'x86' } else { 'x64' }
    python scripts/stage-windows.py --build $folder --arch $label
    if ($LASTEXITCODE -ne 0) { throw "Packaging failed: $architecture" }
}
$compiler = Get-Command ISCC.exe -ErrorAction SilentlyContinue
$iscc = if ($compiler) { $compiler.Source } else { "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
if (-not (Test-Path $iscc)) { throw 'Install Inno Setup 6 from its official website to build the installer.' }
& $iscc platforms/windows/Installer.iss
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed' }
$checksums = Get-ChildItem dist/JianfanZhuyin-*-windows-x64.exe | ForEach-Object {
    $hash = Get-FileHash $_.FullName -Algorithm SHA256
    "{0}  {1}" -f $hash.Hash.ToLowerInvariant(), $_.Name
}
$checksums | Set-Content -Encoding utf8NoBOM dist/SHA256SUMS-Windows.txt
$checksums

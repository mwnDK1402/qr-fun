Set-Location $PSScriptRoot

cl /nologo /c qrcodegen.c /Foqrcodegen.obj > $null
if ($LASTEXITCODE -ne 0) { throw "Compilation failed" }

New-Item -ItemType Directory -Force -Path "..\lib" | Out-Null

lib /NOLOGO /out:..\lib\qrcodegen.lib qrcodegen.obj > $null
if ($LASTEXITCODE -ne 0) { throw "Library creation failed" }

Remove-Item qrcodegen.obj

Write-Host "QR Code library built successfully."

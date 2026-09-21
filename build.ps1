$ErrorActionPreference = 'Stop'
$versionLine = Select-String -LiteralPath (Join-Path $PSScriptRoot 'forever_thanks.toc') -Pattern '^## Version: (.+)$'
$version = $versionLine.Matches[0].Groups[1].Value.Trim()
$dist = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$zipPath = Join-Path $dist "forever_thanks-$version.zip"
if (Test-Path -LiteralPath $zipPath) { throw "Package already exists: $zipPath" }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Create')
try {
    foreach ($name in @('forever_thanks.toc', 'forever_thanks.lua', 'README.md', 'CHANGELOG.md', 'icon.png')) {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $PSScriptRoot $name), "forever_thanks/$name") | Out-Null
    }
} finally { $zip.Dispose() }
Get-Item -LiteralPath $zipPath

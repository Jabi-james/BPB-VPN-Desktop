$ErrorActionPreference = 'Stop'

$rc = "windows/runner/Runner.rc"
if (!(Test-Path $rc)) { throw "Windows resource file not found: $rc" }
$icon = "windows/runner/resources/app_icon.ico"
if (!(Test-Path $icon)) { throw "BPB Windows app icon not found: $icon" }

$rcSource = Get-Content $rc -Raw
if ($rcSource -notmatch 'app_icon\.ico') { throw "Windows runner resource file does not reference app_icon.ico." }

$rcSource = [regex]::Replace($rcSource, '(?m)^\s*VALUE "CompanyName".*\r?\n', '')
$rcSource = [regex]::Replace($rcSource, '(?m)^\s*VALUE "FileDescription".*\r?\n', '')
$rcSource = [regex]::Replace($rcSource, '(?m)^\s*VALUE "FileVersion".*\r?\n', '')
$rcSource = [regex]::Replace($rcSource, '(?m)^\s*VALUE "ProductName".*$', '            VALUE "ProductName", "BPB VPN Desktop\0"')
$rcSource = [regex]::Replace($rcSource, '(?m)^\s*VALUE "ProductVersion".*$', '            VALUE "ProductVersion", "1.3.0\0"')

# Rebuild the StringFileInfo entries line-by-line so Comments is guaranteed
# to sit inside the same language/code-page StringTable as ProductName.
$lines = $rcSource -split "\r?\n"
$updatedLines = [System.Collections.Generic.List[string]]::new()
$commentsInserted = $false
foreach ($line in $lines) {
    if ($line -match '^\s*VALUE "Comments"') { continue }
    $updatedLines.Add($line)
    if ($line -match '^\s*VALUE "ProductVersion"') {
        $updatedLines.Add('            VALUE "Comments", "Developed by NotDev\0"')
        $commentsInserted = $true
    }
}
if (!$commentsInserted) { throw "ProductVersion resource entry is missing; cannot insert Comments." }
$rcSource = $updatedLines -join [Environment]::NewLine

$rcSource = [regex]::Replace($rcSource, '(?m)^FILEVERSION.*$', 'FILEVERSION 0,0,0,0')
$rcSource = [regex]::Replace($rcSource, '(?m)^PRODUCTVERSION.*$', 'PRODUCTVERSION 1,3,0,0')

if ($rcSource -match 'VALUE "CompanyName"|VALUE "FileDescription"|VALUE "FileVersion"' -or
    !$rcSource.Contains('VALUE "ProductName", "BPB VPN Desktop\0"') -or
    !$rcSource.Contains('VALUE "ProductVersion", "1.3.0\0"') -or
    !$rcSource.Contains('VALUE "Comments", "Developed by NotDev\0"') -or
    ([regex]::Matches($rcSource, 'VALUE "Comments"')).Count -ne 1) {
    throw "Windows VERSIONINFO metadata did not match the requested BPB fields."
}

[System.IO.File]::WriteAllText($rc, $rcSource, [System.Text.UTF8Encoding]::new($false))
$written = Get-Content $rc -Raw
if ($written -notmatch '(?s)VALUE "ProductVersion", "1\.3\.0\\0".*?VALUE "Comments", "Developed by NotDev\\0"') {
    throw "Comments was not written immediately after ProductVersion inside the VERSIONINFO string table."
}
Write-Host "Verified Runner.rc contains ProductVersion and Comments in the VERSIONINFO string table."
Write-Host "Windows EXE metadata configured for BPB VPN Desktop 1.3.0."

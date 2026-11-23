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

if ($rcSource -notmatch 'VALUE "Comments"') {
    $productVersionLine = [regex]::Match($rcSource, '(?m)^\s*VALUE "ProductVersion".*$')
    if (!$productVersionLine.Success) { throw "ProductVersion resource entry is missing." }
    $commentsLine = [Environment]::NewLine + '            VALUE "Comments", "Developed by NotDev\0"'
    $rcSource = $rcSource.Insert($productVersionLine.Index + $productVersionLine.Length, $commentsLine)
} else {
    $rcSource = [regex]::Replace($rcSource, '(?m)^\s*VALUE "Comments".*$', '            VALUE "Comments", "Developed by NotDev\0"')
}

$rcSource = [regex]::Replace($rcSource, '(?m)^FILEVERSION.*$', 'FILEVERSION 0,0,0,0')
$rcSource = [regex]::Replace($rcSource, '(?m)^PRODUCTVERSION.*$', 'PRODUCTVERSION 1,3,0,0')

if ($rcSource -match 'VALUE "CompanyName"|VALUE "FileDescription"|VALUE "FileVersion"' -or
    !$rcSource.Contains('VALUE "ProductName", "BPB VPN Desktop\0"') -or
    !$rcSource.Contains('VALUE "ProductVersion", "1.3.0\0"') -or
    !$rcSource.Contains('VALUE "Comments", "Developed by NotDev\0"')) {
    throw "Windows VERSIONINFO metadata did not match the requested BPB fields."
}

Set-Content -Path $rc -Value $rcSource -Encoding utf8
Write-Host "Windows EXE metadata configured for BPB VPN Desktop 1.3.0."

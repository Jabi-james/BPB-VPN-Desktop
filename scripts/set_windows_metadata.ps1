$ErrorActionPreference = 'Stop'

$rc = "windows/runner/Runner.rc"
if (!(Test-Path $rc)) { throw "Windows resource file not found: $rc" }
$icon = "windows/runner/resources/app_icon.ico"
if (!(Test-Path $icon)) { throw "BPB Windows app icon not found: $icon" }

$rcSource = Get-Content $rc -Raw
if ($rcSource -notmatch 'app_icon\.ico') { throw "Windows runner resource file does not reference app_icon.ico." }

# Keep only the requested VERSIONINFO string fields.
$rcSource = [regex]::Replace($rcSource, '(?m)^[ \t]*VALUE "CompanyName".*\r?\n', '')
$rcSource = [regex]::Replace($rcSource, '(?m)^[ \t]*VALUE "FileDescription".*\r?\n', '')
$rcSource = [regex]::Replace($rcSource, '(?m)^[ \t]*VALUE "FileVersion".*\r?\n', '')
$rcSource = [regex]::Replace($rcSource, '(?m)^[ \t]*VALUE "Comments".*\r?\n', '')
$rcSource = [regex]::Replace($rcSource, '(?m)^[ \t]*VALUE "ProductName".*$', '            VALUE "ProductName", "BPB VPN Desktop\0"')
$rcSource = [regex]::Replace($rcSource, '(?m)^[ \t]*VALUE "ProductVersion".*$', '            VALUE "ProductVersion", "1.3.0\0"')

$lines = $rcSource -split "\r?\n"
$updatedLines = [System.Collections.Generic.List[string]]::new()
$companyInserted = $false
foreach ($line in $lines) {
    $updatedLines.Add($line)
    if ($line -match '^[ \t]*VALUE "ProductVersion"') {
        $updatedLines.Add('            VALUE "CompanyName", "NotDev\0"')
        $companyInserted = $true
    }
}
if (!$companyInserted) { throw "ProductVersion resource entry is missing; cannot insert CompanyName." }
$rcSource = $updatedLines -join [Environment]::NewLine

# Runner.rc from Flutter 3.47.7 indents these directives by one space.
# Match optional horizontal indentation so the fixed numeric versions are actually updated.
$rcSource = [regex]::Replace($rcSource, '(?m)^[ \t]*FILEVERSION[ \t]+.*$', ' FILEVERSION 0,0,0,0')
$rcSource = [regex]::Replace($rcSource, '(?m)^[ \t]*PRODUCTVERSION[ \t]+.*$', ' PRODUCTVERSION 1,3,0,0')

if ($rcSource -match 'VALUE "FileDescription"|VALUE "FileVersion"|VALUE "Comments"' -or
    !$rcSource.Contains('VALUE "ProductName", "BPB VPN Desktop\0"') -or
    !$rcSource.Contains('VALUE "ProductVersion", "1.3.0\0"') -or
    !$rcSource.Contains('VALUE "CompanyName", "NotDev\0"') -or
    $rcSource -notmatch '(?m)^[ \t]*FILEVERSION 0,0,0,0$' -or
    $rcSource -notmatch '(?m)^[ \t]*PRODUCTVERSION 1,3,0,0$') {
    throw "Windows VERSIONINFO metadata did not match the requested BPB fields."
}

[System.IO.File]::WriteAllText($rc, $rcSource, [System.Text.UTF8Encoding]::new($false))
$written = Get-Content $rc -Raw
if ($written -notmatch '(?s)VALUE "ProductVersion", "1\.3\.0\\0".*?VALUE "CompanyName", "NotDev\\0"' -or
    $written -notmatch '(?m)^[ \t]*FILEVERSION 0,0,0,0$' -or
    $written -notmatch '(?m)^[ \t]*PRODUCTVERSION 1,3,0,0$') {
    throw "Windows VERSIONINFO metadata was not written exactly as requested."
}
Write-Host "Configured Runner.rc: ProductName=BPB VPN Desktop, ProductVersion=1.3.0, CompanyName=NotDev; unwanted string fields are absent; fixed versions are File=0.0.0.0 and Product=1.3.0.0."

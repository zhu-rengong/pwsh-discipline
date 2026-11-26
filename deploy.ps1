#Requires -Version 7.0
<#
    Deploys this skill from its development directory to the DSH skill root.

        .\deploy.ps1                    # -> $DSH_HOME\skills\pwsh-discipline
        .\deploy.ps1 -Verify            # also run the deployed probe afterwards
        .\deploy.ps1 -Destination <p>   # explicit target

    The source tree is never the deployment tree: this script copies SKILL.md and
    the references/ and scripts/ subtrees, leaving any unrelated files in the
    target untouched.
#>

[CmdletBinding()]
param(
    [string]$Destination,
    [switch]$Verify
)

$ErrorActionPreference = 'Stop'

$source = $PSScriptRoot

function Write-Step {
    param([string]$Message)
    Write-Output ('  ' + $Message)
}

if ([string]::IsNullOrWhiteSpace($Destination)) {
    $dshHome = $env:DSH_HOME
    if ([string]::IsNullOrWhiteSpace($dshHome)) {
        $dshHome = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dsh'
    }
    $Destination = Join-Path $dshHome 'skills\pwsh-discipline'
}

# ---------------------------------------------------------------- preflight

$skillFile = Join-Path $source 'SKILL.md'
if (-not (Test-Path -LiteralPath $skillFile)) {
    throw "SKILL.md not found next to this script: $skillFile"
}

$raw = Get-Content -LiteralPath $skillFile -Raw
$lines = $raw -split "`r?`n"
if ($lines[0] -ne '---') { throw 'SKILL.md does not start with YAML frontmatter' }

$closing = -1
for ($index = 1; $index -lt $lines.Count; $index++) {
    if ($lines[$index] -eq '---') { $closing = $index; break }
}
if ($closing -lt 0) { throw 'SKILL.md frontmatter is not terminated' }

$frontmatter = $lines[1..($closing - 1)]
$nameLine = $frontmatter | Where-Object { $_ -match '^name:\s*\S' } | Select-Object -First 1
$descriptionLine = $frontmatter | Where-Object { $_ -match '^description:\s*\S' } | Select-Object -First 1
if ($null -eq $nameLine) { throw 'frontmatter is missing a name field' }
if ($null -eq $descriptionLine) { throw 'frontmatter is missing a description field' }

$skillName = ($nameLine -replace '^name:\s*', '').Trim()
if ($skillName -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
    throw "frontmatter name '$skillName' is not kebab-case: DSH would silently skip this skill"
}

$description = ($descriptionLine -replace '^description:\s*', '').Trim()
if ($description.Length -gt 500) {
    throw "description is $($description.Length) characters; the model catalog truncates at 500"
}

$leaf = Split-Path -Path $Destination -Leaf
if ($leaf -ne $skillName) {
    throw "destination leaf '$leaf' does not match the skill name '$skillName'; DSH resolves by frontmatter name but the directory name should agree"
}

Write-Output "deploy $skillName"
Write-Step "source      $source"
Write-Step "destination $Destination"
Write-Step "description $($description.Length) chars"

# ---------------------------------------------------------------- copy

New-Item -ItemType Directory -Path $Destination -Force | Out-Null
Copy-Item -LiteralPath $skillFile -Destination (Join-Path $Destination 'SKILL.md') -Force

foreach ($subtree in @('references', 'scripts')) {
    $from = Join-Path $source $subtree
    if (-not (Test-Path -LiteralPath $from)) { continue }
    $to = Join-Path $Destination $subtree
    New-Item -ItemType Directory -Path $to -Force | Out-Null
    Get-ChildItem -LiteralPath $from -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($from.Length + 1)
        $target = Join-Path $to $relative
        $parent = Split-Path -Path $target -Parent
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    }
}

# ---------------------------------------------------------------- report

$deployed = Get-ChildItem -LiteralPath $Destination -Recurse -File |
    Sort-Object FullName |
    Select-Object @{ n = 'File'; e = { $_.FullName.Substring($Destination.Length + 1) } }, Length
Write-Output '  wrote:'
$deployed | ForEach-Object { Write-Step ('{0,-42} {1,7} B' -f $_.File, $_.Length) }

if (-not $Verify) {
    Write-Output 'done. Track the watcher: the skill catalog refreshes on its own; -Verify also proves the copy runs.'
    exit 0
}

$probe = Join-Path $Destination 'scripts\probe-pwsh-semantics.ps1'
if (-not (Test-Path -LiteralPath $probe)) {
    throw "no probe deployed at $probe"
}

Write-Output 'verifying the deployed copy:'
& $probe
$probeExit = $LASTEXITCODE
if ($probeExit -ne 0) {
    # The probe exits 0 by design; a non-zero code here means it was modified or blocked.
    throw "deployed probe exited $probeExit; it must always exit 0"
}

exit 0

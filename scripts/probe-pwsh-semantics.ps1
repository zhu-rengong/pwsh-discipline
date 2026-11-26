#Requires -Version 7.0
<#
    Re-verifies every rule in ../SKILL.md against the running PowerShell.

    Run it through the DSH `pwsh` tool after upgrading DSH or PowerShell:

        & '<skill-directory>\scripts\probe-pwsh-semantics.ps1'

    One line per check: PASS / FAIL / SKIP. The script always exits 0 so a
    failing check can never be mistaken for a failing tool call.
#>

$ErrorActionPreference = 'Stop'
$script:passed = 0
$script:failed = 0
$script:skipped = 0
$script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('pwsh-discipline-probe-' + [guid]::NewGuid().ToString('N'))

function Report {
    param([string]$Id, [string]$State, [string]$Note)
    switch ($State) {
        'PASS' { $script:passed++ }
        'FAIL' { $script:failed++ }
        'SKIP' { $script:skipped++ }
    }
    Write-Output ('{0,-4} [{1}] {2}' -f $State, $Id, $Note)
}

function Check {
    param([string]$Id, [scriptblock]$Body, [string]$Note)
    try {
        if (& $Body) { Report $Id 'PASS' $Note } else { Report $Id 'FAIL' $Note }
    } catch {
        Report $Id 'FAIL' ($Note + ' -- ' + $_.Exception.Message)
    }
}

function Get-ChildExit {
    param([string]$Text)
    & pwsh -NoLogo -NoProfile -NonInteractive -Command $Text 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Get-Rendered {
    param([scriptblock]$Body, [int]$Width)
    return (& $Body | Out-String -Width $Width).Trim()
}

function Get-DisplayWidth {
    param([string]$Text)
    $width = 0
    foreach ($character in $Text.ToCharArray()) {
        $code = [int]$character
        $wide = ($code -ge 0x1100 -and $code -le 0x115F) -or
                ($code -ge 0x2E80 -and $code -le 0xA4CF) -or
                ($code -ge 0xAC00 -and $code -le 0xD7A3) -or
                ($code -ge 0xF900 -and $code -le 0xFAFF) -or
                ($code -ge 0xFE30 -and $code -le 0xFE6F) -or
                ($code -ge 0xFF00 -and $code -le 0xFF60) -or
                ($code -ge 0xFFE0 -and $code -le 0xFFE6)
        $width += if ($wide) { 2 } else { 1 }
    }
    return $width
}

Write-Output ('probe target: PowerShell ' + $PSVersionTable.PSVersion + ' on ' + [System.Environment]::OSVersion.VersionString)

# ---------------------------------------------------------------- exit codes

Check 'E5a' { (Get-ChildExit 'cmd /c exit 3') -eq 1 } 'a failing native call alone exits 1'
Check 'E5b' { (Get-ChildExit 'cmd /c exit 3; "done"') -eq 0 } 'a successful statement after it masks the failure'
Check 'E5c' { (Get-ChildExit 'cmd /c exit 3; exit $LASTEXITCODE') -eq 3 } 'exit $LASTEXITCODE restores the real code'
Check 'E5d' { (Get-ChildExit 'exit 7') -eq 7 } 'explicit exit n is preserved'
Check 'E5e' { (Get-ChildExit 'throw "boom"') -eq 1 } 'a terminating error exits 1'
Check 'E5f' {
    (Get-ChildExit 'Get-Item -LiteralPath ''C:\dsh-probe-missing'' -ErrorAction SilentlyContinue') -eq 1
} 'a swallowed error as the last statement still exits 1'
Check 'E5g' {
    (Get-ChildExit 'Get-Item -LiteralPath ''C:\dsh-probe-missing'' -ErrorAction SilentlyContinue; "ok"') -eq 0
} 'a successful statement after a swallowed error exits 0'

Check 'E6' {
    if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git not installed' }
    (Get-ChildExit 'git -C C:\ log -1; exit $LASTEXITCODE') -eq 128
} 'a guarded native failure returns its own code (git: 128)'

Check 'E7' {
    New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
    $plain = Join-Path $script:tempRoot 'plain.ps1'
    $explicit = Join-Path $script:tempRoot 'explicit.ps1'
    Set-Content -LiteralPath $plain -Value 'cmd /c exit 5' -Encoding utf8
    Set-Content -LiteralPath $explicit -Value 'cmd /c exit 5; exit $LASTEXITCODE' -Encoding utf8
    & pwsh -NoLogo -NoProfile -NonInteractive -File $plain 2>&1 | Out-Null
    $plainCode = $LASTEXITCODE
    & pwsh -NoLogo -NoProfile -NonInteractive -File $explicit 2>&1 | Out-Null
    $explicitCode = $LASTEXITCODE
    ($plainCode -eq 0) -and ($explicitCode -eq 5)
} 'a -File child only propagates an explicit exit'

# ------------------------------------------------------------------ rendering

Check 'E9' { $Host.UI.RawUI.BufferSize.Width -eq 120 } ('console buffer width is 120 (got ' + $Host.UI.RawUI.BufferSize.Width + ')')

Check 'E10' {
    $long = [pscustomobject]@{ V = ('x' * 300) }
    $line = (& { $long | Format-Table | Out-String }) -split "`n" | Where-Object { $_ -match 'xxx' } | Select-Object -First 1
    $line.TrimEnd().Length -eq 120
} 'Out-String without -Width clips at 120 whatever the buffer width is'

Check 'E11' {
    $long = [pscustomobject]@{ V = ('x' * 300) }
    $line = (& { $long | Format-Table | Out-String -Width 200 }) -split "`n" | Where-Object { $_ -match 'xxx' } | Select-Object -First 1
    $line.TrimEnd().Length -eq 200
} 'Out-String -Width 200 raises the clip to 200'

Check 'E12' {
    $rows = @([pscustomobject]@{ Name = ('n' * 40); Middle = ('m' * 40); Last = ('l' * 40) })
    $plain = Get-Rendered { $rows | Format-Table } 120
    $sized = Get-Rendered { $rows | Format-Table -AutoSize } 120
    $plain -eq $sized
} '-AutoSize does not prevent truncation at the default width'

Check 'E13' {
    $four = Get-Rendered { [pscustomobject]@{ A = 1; B = 2; C = 3; D = 4 } } 200
    $four.Contains('A B C D') -and -not $four.Contains('A : 1')
} 'four properties render as a table'

Check 'E14' {
    $five = Get-Rendered { [pscustomobject]@{ A = 1; B = 2; C = 3; D = 4; E = 5 } } 200
    $five.Contains('A : 1')
} 'five properties silently render as a list'

Check 'E15' {
    $mixed = Get-Rendered { [pscustomobject]@{ A = 1; B = 2 }; [pscustomobject]@{ X = 9; Y = 8; Z = 7 } } 200
    -not $mixed.Contains('9 8 7')
} 'a second, differently shaped object renders blank'

Check 'E16' {
    New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
    1..4 | ForEach-Object {
        Set-Content -LiteralPath (Join-Path $script:tempRoot ('big' + $_ + '.txt')) -Value ('x' * 600) -Encoding utf8
    }
    Set-Content -LiteralPath (Join-Path $script:tempRoot 'small.txt') -Value 'x' -Encoding utf8
    $broken = (Get-ChildItem -LiteralPath $script:tempRoot -File | Format-Table | Measure-Object -Property Length -Sum)
    $fixed = (Get-ChildItem -LiteralPath $script:tempRoot -File | Where-Object { $_.Length -gt 500 } | Measure-Object -Property Length -Sum)
    ($broken.Count -eq 0) -and ($fixed.Count -eq 4)
} 'Format-Table before an aggregate yields nothing'

Check 'E17' {
    $before = $FormatEnumerationLimit
    $clipped = Get-Rendered { [pscustomobject]@{ Name = 'n'; Tags = @('t1','t2','t3','t4','t5','t6') } | Format-List } 200
    $global:FormatEnumerationLimit = 20
    $full = Get-Rendered { [pscustomobject]@{ Name = 'n'; Tags = @('t1','t2','t3','t4','t5','t6') } | Format-List } 200
    $global:FormatEnumerationLimit = $before
    ($before -eq 4) -and $clipped.Contains('t4…') -and $full.Contains('t6')
} 'collections clip at four items by default'

Check 'E18' {
    $rows = @([pscustomobject]@{ Name = '主机文件'; Size = 824 }, [pscustomobject]@{ Name = 'networks'; Size = 3683 })
    $lines = (Get-Rendered { $rows | Format-Table -AutoSize } 200) -split "`n"
    $cjk = $lines | Where-Object { $_ -match '824' } | Select-Object -First 1
    $ascii = $lines | Where-Object { $_ -match '3683' } | Select-Object -First 1
    (Get-DisplayWidth $cjk.TrimEnd()) -eq (Get-DisplayWidth $ascii.TrimEnd())
} 'tables align CJK by display width'

Check 'E19' {
    $padded = '{0,-12}' -f '主机文件'
    $plain = '{0,-12}' -f 'networks'
    (Get-DisplayWidth $padded) -ne (Get-DisplayWidth $plain)
} 'the -f recipe counts characters, so it misaligns CJK'

Check 'E20' {
    $deep = [pscustomobject]@{ a = [pscustomobject]@{ b = [pscustomobject]@{ c = [pscustomobject]@{ d = 1 } } } }
    $warnings = $null
    $shallow = ($deep | ConvertTo-Json -Compress -WarningVariable warnings -WarningAction SilentlyContinue)
    $full = ($deep | ConvertTo-Json -Depth 10 -Compress)
    $shallow.Contains('@{d=1}') -and ($warnings.Count -eq 1) -and $full.Contains('"d":1')
} 'ConvertTo-Json defaults to depth 2 and warns'

Check 'E21' { $null -eq (@() | ConvertTo-Json -Compress) } 'an empty array serializes to nothing at all, not []'

Check 'E22' {
    New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
    $errFile = Join-Path $script:tempRoot 'stderr.txt'
    $stdout = & pwsh -NoLogo -NoProfile -NonInteractive -Command 'Write-Warning "probe-warning"' 2> $errFile
    $warningOnStdout = ($stdout -join "`n").Contains('probe-warning')
    $stderrText = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue
    $stderrEmpty = [string]::IsNullOrWhiteSpace($stderrText)
    $warningOnStdout -and $stderrEmpty
} 'Write-Warning lands on stdout'

Check 'E23' {
    $styled = $PSStyle.OutputRendering -eq 'PlainText'
    $noColor = $env:NO_COLOR -eq '1'
    $styled -and $noColor
} 'output is plain text with no ANSI escapes'

Check 'E24' { $PSNativeCommandArgumentPassing -eq 'Windows' } ('native argument passing defaults to Windows (got ' + $PSNativeCommandArgumentPassing + ')')

# --------------------------------------------------------------- environment
# M1 is informational only: the harness profile decides whether a project-level
# skill root exists, so its absence is not a defect. It never fails the run.

if ($null -eq (Get-Command rg -ErrorAction SilentlyContinue)) {
    Report 'M1' 'SKIP' 'ripgrep absent; use Select-String or the grep tool'
} else {
    Report 'M1' 'SKIP' 'ripgrep present; prefer it over Select-String'
}

if (Test-Path -LiteralPath $script:tempRoot) {
    Remove-Item -LiteralPath $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output ('summary: {0} passed, {1} failed, {2} skipped' -f $script:passed, $script:failed, $script:skipped)
exit 0

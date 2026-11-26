# Command authoring — evidence

Every claim here was measured through the `pwsh` tool on 2026-11-26 with PowerShell 7.7.0 (`PSVersionTable`) on Windows 10.0.19045, DSH 0.2.2-rc.5. Reproduce a row by running the command shown with the `pwsh` tool.

Skill section: **2. Write a readable command**.

## C-a — Multi-line bodies beat one-line commands

Same failure, two shapes. Multi-line:

```powershell
Write-Output 'a'
Get-Item -LiteralPath 'C:\nope-b' -ErrorAction Stop
```

```
a
Get-Item:
Line |
   2 |  Get-Item -LiteralPath 'C:\nope-b' -ErrorAction Stop
     |  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | 找不到路径“C:\nope-b”，因为该路径不存在。
```

One line, `;`-joined:

```powershell
Write-Output 'a'; Get-Item -LiteralPath 'C:\nope-a' -ErrorAction Stop
```

```
a
Get-Item: 找不到路径“C:\nope-a”，因为该路径不存在。
```

- **Verdict:** the multi-line form carries line number, source line, and caret span; the single-line form carries a message and nothing else. Generate multi-line bodies whenever a call has more than a statement or two.
- Line numbers count physical lines. Attaching `;` to a line does not shift them: a semicolon-terminated three-line body still reports `Line | 2`.
- The executor prepends its UTF-8 preamble as line 1 of the same `-Command` text, so a reported `Line | 2` is the second line **of your command**. Do not compensate for the preamble in your own line numbering.

### A parse error is silent

Every malformed body tried through `-Command` — `if (`, `Get-Item |`, `try { }`, an unterminated quote, an unclosed `@{` — produced **0 bytes of stdout, 0 bytes of stderr, and exit 1**. The tool shows `(no output)` plus `[exit code: 1]`, which is indistinguishable from an interrupted call. Real `ParserError` text only appears when the text is run with `-File`.

So: `(no output)` with a non-zero code on a fresh call is a reason to suspect your own syntax first, and to re-send the body in smaller pieces before assuming the tool failed.

## C-b — Comments and here-strings survive the round trip

```powershell
# why: probe line numbering
$t = @'
line-one
line-two
'@
Write-Output $t
```

```
line-one
line-two
```

- Single- and double-quoted here-strings both work; the closing `'@` / `"@` must start at column 1.
- Comments reach the interpreter but **not** the failure excerpt. Measured with three comment lines above the failing statement: the excerpt shows only `Line | 4 | Get-Item …`. A `# why` appended to the failing statement itself *is* echoed with it, because it shares the line the excerpt reproduces.

## C-c — Continuation: pipes yes, backticks no

All three forms run:

```powershell
# trailing pipe
Get-ChildItem -LiteralPath <dir> -File |
  Where-Object { $_.Length -gt 500 } |
  Select-Object Name, Length

# leading pipe (PowerShell 7)
Get-ChildItem -LiteralPath <dir> -File
  | Select-Object -First 2

# backtick continuation
Get-ChildItem `
  -LiteralPath <dir> `
  -File
```

- **Backtick risk:** the continuation character is a backtick followed by a newline. A space after the backtick ends the statement early, and the failure surfaces on the *next* line as `term '-LiteralPath' 不会被识别为...` with a caret span and exit 1 — a loud but misleading "command not found" rather than a parse error, which is easy to misread as a missing command. Avoid backtick continuation in a command you generate.
- Pipes are the same token at the end of one line or the start of the next; both are safe.

## C-d — Splatting for many arguments

```powershell
$params = @{ LiteralPath = 'C:\Windows\System32\drivers\etc'; Filter = 'hosts'; ErrorAction = 'Stop' }
Get-ChildItem @params | Select-Object Name, Length
```

One long argument list becomes one short line, and the run can change a parameter without rewriting the call.

## C-e — Make the exit code meaningful

| Body (last statement decides) | Exit |
|---|---|
| `cmd /c exit 3` | **1** |
| `cmd /c exit 3;` | **1** |
| `cmd /c exit 3; "done"` | **0** |
| `cmd /c exit 3; exit $LASTEXITCODE` | **3** |
| `cmd /c exit 9; Write-Output "LAST=$LASTEXITCODE"` | **0** (body prints `LAST=9`) |
| `git -C C:\ log -1` | **1** |
| `git -C C:\ log -1; exit $LASTEXITCODE` | **128** |
| `where.exe <missing>` | **1** |
| `try { cmd /c exit 4 } catch { exit 1 }` | **1** |
| `exit 7` | **7** |
| `exit $LASTEXITCODE` with `$LASTEXITCODE` unset | **0** |
| `throw "boom"` | **1** |
| cmdlet non-terminating error last, e.g. `Get-Item C:\nope` | **1** |
| same error, then `"ok"` | **0** |

Two mechanisms produce this:

1. PowerShell's own exit code is whichever path the host takes: a terminating error yields 1; a run that ends after a failed non-terminating error also yields 1; a run that continues past it to a successful statement yields 0.
2. `$LASTEXITCODE` is only promoted to the process exit code when the **native** call is the last statement of the `-Command` text. Any later statement — even one that changes nothing — discards it.

Practical rules:

- Terminating failures need no extra code; they already exit 1.
- When the exact native code matters, and only then, finish with a guard. The naive guard is wrong:

```powershell
# WRONG: reports success when the native command never ran
git status --porcelain
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
```

  With a missing binary, `$LASTEXITCODE` is `$null`; `$null -ne 0` is **true**, so the branch runs and `exit $null` becomes `exit 0` — a hard failure reported as success. Measured:

  | Body | Exit |
  |---|---|
  | `definitely-not-a-command-xyz; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }` | **0** |
  | `$code = 1; definitely-not-a-command-xyz; if ($null -ne $LASTEXITCODE) { $code = $LASTEXITCODE }; exit $code` | **1** |
  | `$code = 1; cmd /c exit 3; if ($null -ne $LASTEXITCODE) { $code = $LASTEXITCODE }; exit $code` | **3** |
  | `$code = 1; cmd /c exit 0; if ($null -ne $LASTEXITCODE) { $code = $LASTEXITCODE }; exit $code` | **0** |

  The safe shape defaults to failure and overwrites only on a confirmed native result:

```powershell
$code = 1
git status --porcelain
if ($null -ne $LASTEXITCODE) { $code = $LASTEXITCODE }
exit $code
```

- `$PSNativeCommandUseErrorActionPreference = $true` plus `$ErrorActionPreference = 'Stop'` converts a non-zero native exit into a terminating error (`NativeCommandExitException`). Use it to abort a multi-step run at the first failing native call; do not use it when you need the code itself, because the exception path yields 1.

## C-f — Nested scripts do not propagate their status

| Nested script | Exit |
|---|---|
| `script` whose body is `cmd /c exit 5`, launched with `pwsh -File script.ps1` | **0** |
| same body plus `exit $LASTEXITCODE` | **5** |

A `-File` child only returns a non-zero code when it exits explicitly. When calling a script you did not write, check its output or its own files rather than the wrapper's exit code.

## C-g — Error rendering modes

Default `ConciseView` is the shortest and needs no configuration; this is what the tool shows unless a command changes it.

```powershell
$ErrorView = 'NormalView'   # adds 在 行:1 字符:28 + CategoryInfo + FullyQualifiedErrorId
$ErrorView = 'DetailedView' # 60+ lines of exception, stack, and environment dump
```

Do not set either. `DetailedView` on a single failure overflows a useful share of the result, and both are locale-dependent.

## C-h — Strictness

`Set-StrictMode -Version Latest` turns an undefined-property read into a terminating error (`PropertyNotFoundException`, exit 1). Useful when a script must not silently proceed on a missing field; avoid it for exploratory one-liners where a `$null` is an expected outcome.

## C-i — Size limits

A 12 000-character single command ran normally. Size is not the constraint; the result is. Long commands still pay the readability price described in C-a, so prefer a handful of readable lines over one dense line.

## C-j — Native argument passing has three modes

`$PSNativeCommandArgumentPassing` is `Windows` by default here, not `Standard`.

| Mode | A `cmd /c` call that quotes its own argument |
|---|---|
| `Windows` (default) | succeeds — the quotes are re-added the way an older cmdlet expects |
| `Standard` | fails — `The filename, directory name, or volume label syntax is incorrect.` |
| `Legacy` | behaves like `Windows` for this shape |

Measured with `cmd /c "dir /b ""<path>"""`: `Windows` lists the directory, `Standard` reports a syntax error on the same string. A C-runtime program such as `git` accepted the quoted path in all three modes, so the mode only matters for native programs that parse their own command line.

Setting `Standard` is therefore a deliberate change, not a safe default: it makes quoting correct for programs that follow the C runtime rules and simultaneously breaks the ones that relied on the legacy re-quoting. Never set it mid-run expecting the default's behaviour, and never present it as a fix for a quoting problem without reproducing the call in both modes.

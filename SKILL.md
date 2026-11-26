---
name: pwsh-discipline
description: Use before writing any pwsh tool command on Windows. Covers command readability (multi-line bodies, continuation, splatting, true exit codes) and output formatting (tables, lists, JSON, width and truncation traps) so tool results are readable instead of mangled.
whenToUse: Any task that will call the pwsh tool, or that reads PowerShell output and must not misread it. Load it before the first pwsh call in a session; it is cheaper than debugging a misformatted result.
---

# pwsh tool discipline

How to write a `pwsh` command that stays readable, and how to shape its result. Calibrated against DSH 0.2.2-rc.5 `@deepseek-ai/dsh-tool-pwsh` with PowerShell 7.7.0. Sections 3 and 4 are machine-checked by `scripts/probe-pwsh-semantics.ps1`; the rest is evidence recorded in `references/`, which also maps every check id to its section.

## 0. Which pwsh do you have

Check the tool's own parameters first.

- `command` with `description` and `workdir`/`timeoutMs`/`run_in_background` → fresh-process tool. Everything here applies.
- `command` alone → persistent-shell variant: state survives calls, no `run_in_background`, output clips at `maxOutputChars` (16 000) with no spill file. Sections 2–4 apply; the timeout/job guidance in section 6 and the truncation mechanics in section 5 do not.

## 1. Call contract

- No state survives a call: re-declare variables, functions, and the current location in every command.
- Never re-emit the UTF-8 console preamble; the executor prepends it, and a copy shifts every line number you would otherwise read.
- One purpose per call. Batch independent reads, but only reads that cannot fail independently — one shared exit code cannot report two failures.

## 2. Write a readable command

**R-a — Prefer several lines over one long line.** A `;`-joined one-liner reports only `Cmdlet: message`. A multi-line body reports the failing line number with the source line and a caret span, which is what makes the call diagnosable. Keep one line only for one or two trivial statements.

**R-b — Continue with `|`, not backticks.** A trailing backtick followed by a space ends the statement early and surfaces as a confusing "term not recognized" error on the next line, not as a parse error. Pipes work at either end of the line.

**R-c — Splat when a call has many arguments.**

```powershell
$params = @{ LiteralPath = 'C:\Windows\System32\drivers\etc'; Filter = 'hosts'; ErrorAction = 'Stop' }
Get-ChildItem @params | Select-Object Name, Length
```

**R-d — Name the safe parameters.** `-LiteralPath` for any path that may contain `[`, `]`, or `*`; `-ErrorAction Stop` on a step whose failure must abort the call.

**R-e — Make the exit code tell the truth.** A terminating error already exits 1, so `throw` and an unhandled `-ErrorAction Stop` need no help. A native program's own code needs a guard, and the naive guard is a trap: when the native command never ran, `$LASTEXITCODE` is `$null`, `$null -ne 0` is true, and `exit $null` reports **success**. Default the code and overwrite it only after a confirmed result:

```powershell
$code = 1
git status --porcelain
if ($null -ne $LASTEXITCODE) { $code = $LASTEXITCODE }
exit $code
```

Measured: a missing binary exits 1 with this guard and 0 with the naive one; a real failure still reports its own code (3 → 3), and success reports 0.

**R-f — Comment the statement, not the block.** A trailing `# why` on the statement is echoed back with it; comment lines above it never appear in a failure excerpt.

## 3. Read the result instead of guessing

Shape: stdout body, then a `[stderr]` section when stderr produced text, then status markers on the final lines. Empty stdout renders `(no output)`.

Markers, and nothing else, carry status:

| Marker | Meaning |
|---|---|
| `[exit code: N]` | Process exit was non-zero, no signal |
| `[killed by signal: X]` | Terminated by a signal |
| `[timed out after Nms]` | Deadline killed the command; no job exists |
| `[stopped: reason]` | Someone killed the job |
| `[still running after Nms; moved to background job <id>]` | Promoted; collect it, do not re-run |
| `[sandbox: file access denied under <mode> mode]` | Policy denial, not a command bug |

The two timeout markers are mutually exclusive: with a job registry present the expiry *promotes* and you get a job id; only the no-promotion path kills and reports `[timed out ...]`.

**The process exit code is not the command's exit code:**

| Command body | Process exit |
|---|---|
| `cmd /c exit 3` as the last statement | **1** — the real code is lost |
| `cmd /c exit 3; "done"` | **0** |
| `cmd /c exit 3; exit $LASTEXITCODE` | 3 |
| Non-terminating error last (`Get-Item C:\nope`), then a successful cmdlet | 1, then **0** |
| `throw`, or an `-ErrorAction Stop` failure | 1 |
| `pwsh -File script.ps1` whose body never calls `exit` | 0, even when the script failed |

So `[exit code: N]` is the *process* code. When a native program's own code matters, use the R-e guard. A non-zero code with a substantive body is a command failure; the same code with `(no output)` is usually a lost code or an interruption.

## 4. Format the output

The renderer is width-limited: **120 columns** inside the tool, because its stdout is not a console and PowerShell then formats at a fixed width. `Out-String` inherits that width, and it does not follow `$Host.UI.RawUI.BufferSize` — raising the buffer inside a command leaves the clip where it was. Exceeding the width does not shrink earlier columns — **the last column is truncated with `…`**.

**F-1 — Format once, deliberately.** One shape, formatted once, at the end of the pipeline. Never emit raw objects and let the default formatter choose.

**F-2 — Tables, for a few rows of a few columns:**

```powershell
$rows = Get-ChildItem -LiteralPath 'C:\Windows\System32\drivers\etc' -File |
  Select-Object Name, Length, @{ n = 'Modified'; e = { $_.LastWriteTime.ToString('yyyy-MM-dd') } }
($rows | Format-Table -AutoSize | Out-String -Width 200).Trim()
```

The `.Trim()` drops the leading blank line and trailing padding `Out-String` adds. `-AutoSize` does **not** prevent truncation (no observable effect at any width tested); `-Wrap` replaces the ellipsis with continuation lines. Keep the widest column early — the last column is what gets cut.

**F-3 — Lists, for one object with many or long fields:** `Get-Item <path> | Format-List Name, Length, LastWriteTime`. A `[pscustomobject]` with five or more properties and no registered view silently becomes a list; typed objects follow their registered view instead (a 17-property `FileInfo` still renders as the four-column table). State the shape explicitly.

**F-4 — JSON, for data a later step consumes:**

```powershell
$rows = @(Get-ChildItem -LiteralPath <dir> -File | Select-Object Name, Length)
if ($rows.Count -eq 0) { '[]' } else { $rows | ConvertTo-Json -Depth 5 -Compress -WarningAction SilentlyContinue }
```

`-Depth` is mandatory: the default is 2, deeper values degrade to `"@{d=1}"` **and** emit a warning onto stdout, which breaks parsing. An empty pipeline serializes to nothing at all — not `[]`, not an empty string — so branch on emptiness.

**F-5 — Fixed-width text, for lines you will grep later:** `'{0,-14} {1,8}' -f $_.Name, $_.Length`. This counts characters, not display cells, so it misaligns CJK; use a table when the values are not ASCII.

**F-6 — `Format-*` is always the last stage.** Anything after it receives formatting records, not objects: `Measure-Object` reports `Count = 0` and `Where-Object` matches nothing, with no error raised. Filter, sort, and aggregate first.

**F-7 — Two silent shapers.** A collection inside a property renders as `{a, b, c, d…}` because `$FormatEnumerationLimit` is 4. Two differently-shaped objects in one stream render the second as a blank line — an artefact, not missing data.

**F-8 — Summarize before you list.** `Measure-Object` for counts and sums, `Group-Object` for distributions, then detail rows only where they matter.

## 5. Bound the output

A stream that overflows keeps its tail and reports a spill path; an oversized result is then shortened again by the harness, which names its own spill path. Use those paths with `read`, `grep`, or `Get-Content -Tail` rather than re-running a broader command.

Bound at the source: `Get-Content -TotalCount` / `-Tail`, `Select-Object -First` (which stops the upstream generator early), `-File` to skip recursion, and a count before a listing. Read file contents with the dedicated `read`/`grep`/`glob` tools rather than `Get-Content`.

## 6. Time and background

A foreground command that reaches its timeout is promoted to a background job, so collect it with `job_output` (`wait: true`) and never re-run the command. A background job has no timeout at all, so every one you start must be collected or killed before you finish.

## 7. Sandbox and denials

Read the three markers in the tool contract for the mode semantics; the part that is not in the contract:

- Escalation is a one-shot retry of the *same* command. If approvals are disabled in this session, the retry is rejected — report the denial and stop instead of escalating.
- An `EPERM` on a piped grandchild spawn is the confinement boundary, not a defect in your command. Restructure the call rather than retrying it.

## 8. Destructive operations

Print the resolved absolute target first (`Resolve-Path -LiteralPath <path>`, or a plain `Write-Output` of the computed value), then act on that exact literal path in a later statement. This is the one rule that matters *more* as permissions widen: an unconfined session has nothing between a wrong path and data loss.

## 9. Triage

| Symptom | Read it as | Do |
|---|---|---|
| `(no output)` + `[exit code: 1]` | Suspicious first: a parse error is invisible under `-Command` — no stdout, no stderr, code 1 | Re-send the command in smaller pieces and isolate the malformed statement |
| Bare non-zero code, substantive body | The command ran and failed | Read the body; the code may be 1 rather than the program's own |
| Real native code missing | A later statement overwrote it | Apply the R-e guard as the final statement |
| `[timed out after Nms]` | Killed; no job exists | Inspect the partial output, narrow, re-run |
| `[still running after Nms; ...]` | Promoted and still running | `job_output` with `wait: true` |
| `EPERM` on a piped grandchild spawn | Confinement boundary | Restructure; do not retry |
| "only core types" style error | ConstrainedLanguage | Use cmdlets, not .NET |
| Last column ends in `…` | 120-column render width | `Out-String -Width N`, or move the wide column first |
| Warning before a JSON payload | `-Depth` too shallow | Pass `-Depth`, add `-WarningAction SilentlyContinue` |
| Empty output where a list was expected | An empty pipeline serialized to nothing | Branch on emptiness |
| Error text in another language | Localized messages | Match on status and structured properties, never on message text |

## 10. Audit

`scripts/probe-pwsh-semantics.ps1` checks the exit-code and formatting rules — sections 3 and 4 — and prints `PASS`/`FAIL`/`SKIP` per check id. It always exits 0, so a FAIL never masquerades as a failed tool call; `deploy.ps1 -Verify` reads the summary line and is what actually gates a deploy. Run it through the `pwsh` tool after a DSH or PowerShell upgrade. Two checks (`E9`, `E23`) assert tool-host facts — the 120-column format width and the `NO_COLOR`/`PlainText` pair — and report `SKIP` rather than `FAIL` when the probe runs in a real terminal, where both legitimately differ. `references/audit-map.md` maps every check id to the section and reference that owns it; fix the rule there, then re-run.

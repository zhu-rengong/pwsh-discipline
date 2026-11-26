# Audit log

Three audit rounds were run against this skill. Round 1 is the behaviour audit performed by a fresh-context subagent that loaded the skill and exercised it; round 2 is the correction pass that followed; round 3 is the pass triggered by the probe failing three checks when `deploy.ps1 -Verify` ran in a real terminal instead of the `pwsh` tool. Every finding below is either fixed in place or explicitly closed as not-a-defect, with the evidence that supports the call.

## Round 1 — findings and disposition

| # | Finding | Disposition |
|---|---|---|
| H1 | `[timed out after Nms]` and the promoted-job marker were conflated in the triage table; the first has no job id and the second does | **Fixed.** Section 3 now states the two are mutually exclusive, and section 9 separates "killed, no job exists" from "promoted, `job_output`". |
| H2 | The recommended `if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }` guard reports **success** when the native command never ran (`$null -ne 0` is true, and `exit $null` yields 0) | **Fixed.** R-e now shows the trap, its measurement matrix, and the `$code = 1` default-then-overwrite shape. `command-authoring.md` C-e carries the four-case table. |
| H3 | "Above four properties the default formatter switches to a list" was over-general — typed objects follow their registered view | **Fixed.** Section 4 (F-3) and `output-formatting.md` F-default now scope the rule to `[pscustomobject]` with no view, and record that a 17-property `FileInfo` still renders as a table. |
| H4 | A parse error under `-Command` produces no stdout, no stderr, and exit 1 — indistinguishable from an interruption, and the triage table pointed at a `ParserError` string that never appears | **Fixed.** The signature `(no output)` + `[exit code: 1]` is now the first triage row, and `command-authoring.md` C-a documents the six malformed bodies that produced it. The `ParserError` row was removed. |
| H5 | "re-verifies every rule" and "everything else was measured" were false; the probe covers only sections 3–4 | **Fixed.** The header states the real coverage, section 10 repeats it, and `references/audit-map.md` lists what is and is not machine-checked. |
| H6 | Probe check ids (`E5a`, `E16`, …) had no landing point in the references, which used `C-*` and `F-*` ids | **Fixed.** `references/audit-map.md` maps every check id to its section and reference row. |
| M1 | `Out-String` was said to inherit the console buffer width; it does not | **Fixed.** Re-measured: raising `BufferSize` to 200 left the default rendering at 120. The claim is corrected in `SKILL.md` and `local-environment.md`, and the E10 assertion now says "whatever the buffer width is". |
| M2 | Comments were said to appear in a failure excerpt; only a trailing comment on the failing statement does | **Fixed.** R-f and C-b now distinguish the two. |
| M3 | Backtick continuation was described as breaking silently; it breaks loudly as a misleading "term not recognized" | **Fixed.** R-b and C-c corrected. |
| M4 | `$PSNativeCommandArgumentPassing = 'Standard'` was recommended without evidence and is not a safe default | **Fixed.** Section 6 and `command-authoring.md` C-j now record that the default is `Windows`, that the default already passes quoted arguments to C-runtime programs, and that `Standard` changes behaviour for self-parsing programs. |
| M5 | `-Encoding utf8` was presented as if it prevented corruption | **Fixed.** Narrowed to "harmless and self-documenting on PowerShell 7; the risk is the 5.1 fallback", recorded in `local-environment.md`. |
| M6 | Six places restated the tool description and parameter descriptions verbatim | **Fixed.** Section 1 keeps only the state-loss and preamble rules; section 7 says explicitly that the mode semantics live in the tool contract; sections 6/8 keep only the additions. |
| M7 | The local appendix claimed only a handful of built-in aliases exist; there are 135 | **Fixed.** Count and the commonly used ones recorded. |
| M8 | "never from the exit code alone" contradicted its own use of `[exit code: N]` | **Fixed.** Reworded to distinguish the process code from the program's own code. |
| M9 | The F-2 recipe omitted the `.Trim()` the reference requires, leaving a leading blank line | **Fixed.** Both the skill and the reference now end the pipeline with `.Trim()`. |
| M10 | Probe check `M1` could only ever report `SKIP` | **Closed as intentional**, documented in the script and in the audit map: whether a project-level skill root exists is a profile fact, not a defect, so the check reports and never fails the run. |
| M11 | Section 0 said sections 2–5 apply to the persistent variant, but section 5's 64 KB/spill mechanics are fresh-process only | **Fixed.** The exception is now named. |
| M12 | `[killed by signal]` and `[stopped: reason]` were asserted only from source | **Closed.** They remain documented as part of the marker vocabulary, sourced from `dsh-tool-pwsh/src/render.ts`; the audit map lists them under "not machine-checked". |
| M13 | The second truncation layer and `Select-Object -First` early termination were unbacked | **Fixed.** Both were measured and recorded: a 14 432-byte middle omission with its own spill path, and 3 iterations of a 100 000-item generator. |
| M14 | Batching guidance conflicted with the exit-code doctrine | **Fixed.** Section 1 now limits batching to reads that cannot fail independently. |
| L1–L6 | Typo `cdmlet`; self-contradictory `-AutoSize` sentence; "silently … and print a warning"; environment-coupled probe; `#Requires -Version 7.0` could exit non-zero on 5.1; `maxOutputChars` value unstated | **Fixed**, except the `#Requires` line, which is intentional: on a 5.1 host the probe cannot run at all, and aborting is clearer than reporting every check as failed. |

## Round 2 — regression

After the corrections, every command shown in `SKILL.md` was executed verbatim through the `pwsh` tool:

| Recipe | Result |
|---|---|
| F-2 table with `.Trim()` | 5 aligned rows, no leading blank line, no ellipsis |
| R-e guard against `cmd /c exit 3` | `[exit code: 3]` |
| R-e guard against a missing binary | `[exit code: 1]` with the not-found message — the trap case now reports failure |
| F-4 JSON, non-empty | parseable array of two objects |
| F-4 JSON, empty branch | `[]` |
| F-5 fixed-width lines | aligned for ASCII |

The probe reports **25 passed, 0 failed, 1 skipped** and exits 0.

## Round 3 — a terminal run of the probe

A `.\deploy.ps1 -Verify` run from a real terminal (the user's own console, 176 columns) reported three failures that a tool run never shows:

| # | Finding | Disposition |
|---|---|---|
| N1 | `E9` asserted `$Host.UI.RawUI.BufferSize.Width -eq 120`; in a real console it reports that console's width, so the check failed with `got 176` | **Fixed.** `E9` moved behind a `HostCheck` wrapper: it measures the tool host, and outside it reports `SKIP` with the reason. The rule is unchanged — inside the tool the width is 120. |
| N2 | `E10` compared against a literal 120, so it failed for the same reason (`got 176` in the user's console output), and its note ("whatever the buffer width is") described something it never asserted | **Fixed.** The check is now host-independent: long content truncates below its own length, ends in `…`, and a later `BufferSize` change does not move the clip. That last clause is what the note always claimed and never tested; it is now measured in `output-formatting.md` F-where. |
| N3 | `E23` compared `$env:NO_COLOR -eq '1'` and `OutputRendering -eq 'PlainText'`; a terminal has neither, so it failed | **Fixed.** Moved behind `HostCheck` — both values are injected by `dsh-pwsh-local`, so they are host facts, not PowerShell facts. The check also now samples real formatted output for `ESC` instead of trusting the two flags alone. |
| N4 | `deploy.ps1 -Verify` printed the probe output but its gate only inspected the probe's process exit code, which is always 0 by design — so `-Verify` passed a deploy whose probe reported three failures | **Fixed.** The script now parses the `summary:` line and throws on `0 failed` not being true. Verified by injecting an always-failing check into a copy and watching the deploy abort. |
| N5 | The failure message the user saw named only the symptom (`got 176`), not that the number describes the host rather than the skill | **Fixed.** `E9` now names the tool host in both its note and its `SKIP` text, and `SKILL.md` §4 says the 120 is the tool's detached-console width. |

Round 3 was measured across three hosts:

| Host | `RawUI` buffer/window | `Out-String` default | `E9` / `E23` |
|---|---|---|---|
| DSH `pwsh` tool | 120 / 120, `[Console]::WindowWidth` throws `IOException` | 120 | `PASS` |
| Real console, 100 / 176 / 200 columns, stdout attached | matches the console | matches the console | `SKIP` |
| Same console, stdout redirected to a file | 176 (still reports the console) | 120 | `SKIP` |

The last row is the mechanism: when stdout is not a console, PowerShell formats at a fixed width instead of asking the console. The tool always has that shape — `[Console]::WindowWidth` throws there — so it always lands on 120; a terminal the user opened does not, which is why the number cannot be asserted from one.

## Open items

- The probe writes temporary files under `%TEMP%` and removes them in the same run; if it is killed mid-run a `pwsh-discipline-probe-*` directory can survive. It never writes inside the skill directory.
- `E9` and `E23` assert tool-host facts (the 120-column format width, `NO_COLOR`/`PlainText`), so they `SKIP` rather than fail outside the tool. `E10` is host-independent and must pass anywhere. Run the probe through the `pwsh` tool for a full green.
- Escalation and sandbox behaviour are documented from the composition and the tool contract, not exercised live: this profile runs `danger-full-access` with approvals disabled, so no denial can be produced on demand.

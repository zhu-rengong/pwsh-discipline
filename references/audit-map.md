# Audit map

Reverse index from `scripts/probe-pwsh-semantics.ps1` check ids to the section that owns them and the reference that carries the evidence. When a check fails, edit the owning section of `SKILL.md` and the matching reference row, then re-run the probe.

## Checked by the probe

| Check | Asserts | Owning section | Evidence |
|---|---|---|---|
| `E5a` | a failing native call as the last statement exits 1, not its own code | 3 | `command-authoring.md` C-e |
| `E5b` | a successful statement after it masks the failure (exit 0) | 3 | C-e |
| `E5c` | `exit $LASTEXITCODE` restores the real code | 2 (R-e), 3 | C-e |
| `E5d` | `exit n` is preserved | 3 | C-e |
| `E5e` | a terminating error exits 1 | 3 | C-e |
| `E5f` | a swallowed error as the last statement still exits 1 | 3 | C-e |
| `E5g` | a successful statement after a swallowed error exits 0 | 3 | C-e |
| `E6` | a guarded native failure returns its own code (git → 128) | 2 (R-e) | C-e |
| `E7` | a `-File` child propagates only an explicit `exit` | 3 | C-f |
| `E9` | the tool host formats at 120 columns — **tool-host check, `SKIP` elsewhere** | 4 | `output-formatting.md` F-where |
| `E10` | `Out-String` without `-Width` truncates at a fixed width, marked with `…`, and a later `BufferSize` change does not move it | 4 | F-where |
| `E11` | `Out-String -Width 200` raises the clip to 200 | 4 (F-2) | F-where |
| `E12` | `-AutoSize` does not change the rendering | 4 (F-2) | F-autosize |
| `E13` | four properties render as a table | 4 (F-3) | F-default |
| `E14` | five properties render as a list | 4 (F-3) | F-default |
| `E15` | a second, differently shaped object renders blank | 4 (F-7) | F-mixed |
| `E16` | `Format-Table` before an aggregate yields nothing | 4 (F-6) | F-order |
| `E17` | collections clip at four items | 4 (F-7) | F-enum |
| `E18` | tables align CJK by display width | 4 (F-5) | F-cjk |
| `E19` | the `-f` recipe counts characters, so it misaligns CJK | 4 (F-5) | F-cjk |
| `E20` | `ConvertTo-Json` defaults to depth 2 and warns | 4 (F-4) | F-json |
| `E21` | an empty array serializes to nothing at all | 4 (F-4) | F-json |
| `E22` | `Write-Warning` lands on stdout | 4 (F-4) | F-streams |
| `E23` | output is plain text with no ANSI escapes — **tool-host check, `SKIP` elsewhere** | 4 | F-streams |

`HostCheck` is the wrapper that turns a `FAIL` into a `SKIP` when `DSH_SHELL` is unset or stdout is a real console: those two checks measure the tool's host, and a terminal legitimately differs. Every other check must pass in any PowerShell 7 host.

One check asserts a fact `SKILL.md` does not state, because it changes no instruction:

| Check | Asserts | Evidence |
|---|---|---|
| `E24` | native argument passing defaults to `Windows` | `command-authoring.md` C-j — recorded so a future pass does not re-add "set `Standard`" advice |

## Not machine-checked

These sections are evidence-backed but asserted by no probe check, because they depend on an interaction the probe cannot force safely:

| Area | Section | Evidence |
|---|---|---|
| Multi-line error excerpts, comments, continuation, splatting | 2 | `command-authoring.md` C-a, C-b, C-c, C-d |
| Second truncation layer and spill paths | 5 | `output-formatting.md` F-streams; measured twice in this skill's construction |
| Timeout promotion, job collection | 6 | `dsh-tool-pwsh` `render.ts` plus a live promotion observed during construction |
| Sandbox mode semantics, EPERM boundary, escalation-once | 7 | tool contract plus `dsh-sandbox/src/escalation.ts` |
| Destructive-path discipline | 8 | policy, not a measured behaviour |
| Localization, locale-independent matching | 9 | `local-environment.md` |

A preference stated without measurement is labelled as such at the point it appears; everything else in the table above has a reproducing command in its evidence row.

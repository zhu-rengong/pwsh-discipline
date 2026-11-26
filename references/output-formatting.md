# Output formatting — evidence and recipes

Measured through the `pwsh` tool on 2026-11-26, PowerShell 7.7.0, Windows 10.0.19045. Skill section: **4. Format the output**.

## F-where — the render width is 120 inside the tool

Inside the tool the format width is **120**:

| Fact | Value |
|---|---|
| `$Host.UI.RawUI.BufferSize.Width` / `WindowSize.Width` | 120, stable across calls |
| `[Console]::WindowWidth` / `BufferWidth` | throws `IOException: 句柄无效` — no console is attached to the tool process |
| Default rendering of a 300-character value | 120 characters ending in `…` |
| Default rendering after `BufferSize` is raised to 200 in the same command | still 120 |

So the width is not inherited from `$Host.UI.RawUI.BufferSize`: changing that value inside a command does not move the clip, in the same call or a later one. `Out-String -Width` is the only lever.

The number is a property of this host, not of PowerShell. In a real console with stdout still attached, the same rotation gives the console's own width:

| Console `mode con cols=` | `RawUI` buffer/window | `Out-String` default |
|---|---|---|
| 100 | 100 | 100 |
| 176 | 176 | 176 |
| 200 | 200 | 200 |

And once that console's stdout is redirected to a file, the same 176-column console formats at **120** while `RawUI` still reports 176 — a redirected stdout means no console is attached, and PowerShell falls back to a fixed width. That is why `E9` reports `SKIP` outside the tool instead of failing: a terminal has its own width, and only the tool's detached-console shape is fixed at 120.

| `Out-String -Width` | Value length | Rendered line |
|---|---|---|
| (omitted) | 300 | 120 + `…` |
| 200 | 1 000 | 200 + `…` |
| 300 | 1 000 | 300 + `…` |
| 500 | 1 000 | 500 + `…` |
| 1 000 | 1 000 | 1 000, no ellipsis |
| 3 000 | 3 000 | 3 000, no ellipsis |
| 20 000 | 3 000 | 3 000 (stops at content length) |

- The requested width is honoured above 120; there is no return to a narrow default.
- `Out-String -Width 0` throws `ParameterBindingValidationException`.
- `Out-String` returns a string starting with a blank line and ending with one or two blank lines; `.Trim()` produces text that starts and ends exactly at the content.

## F-last — the sacrifice is the last column

Three 40-character columns at the default width:

```
Name                                     Middle                                   Last
----                                     ------                                   ----
nnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnn mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm llllllllllllllllllllllllllllllllllll…
```

At `-Width 200` the same rows render in full. Reordering with `-Property Last, Name, Middle` moves the ellipsis onto whichever column is last.

| Width | Rendered | Ellipsis |
|---|---|---|
| 120 | 120 | yes |
| 160 | 160 | yes |
| 260 | 206 (content length) | no |

**Fix order:** raise the width → move the long column earlier → `-Wrap` → switch to JSON.

`-Wrap` replaces the ellipsis with continuation lines at the effective width. Measured with a 400-character path at width 200: plain `Format-Table` yields one 200-character line ending in `…`, while `-Wrap` yields a full 200-character segment plus a 63-character continuation line and no ellipsis. It composes with `-AutoSize` (byte-identical output) and with `Out-String -Width` (the wrap width follows `-Width`, not the 120 default).

## F-autosize — `-AutoSize` does not prevent truncation

Measured across widths from 20 to 300, 3/8/10-column shapes, `-Wrap` combinations, 300-row samples, and heterogeneous property sets: the rendered text is identical with and without `-AutoSize`, including the ellipsis. Under this tool it has no observable effect. Never recommend it as a truncation fix. (It is still harmless to include, which is why the recipes below keep it.)

## F-default — property count decides Table versus List, for `[pscustomobject]` only

A `[pscustomobject]` with no format view:

| Properties | Default rendering |
|---|---|
| 1–4 | Table |
| 5+ | List (one `Name : Value` block per object) |

Observed: 4 properties → table; 5 properties → `A : 1` / `B : 2` … per row. Because it is a silent switch, state the shape explicitly (`Format-Table` or `Format-List`) whenever the property count is near the boundary or varies between calls.

**Typed objects do not follow this rule.** They render through their registered view: a `FileInfo` with 17 properties still shows the four-column table (`Mode LastWriteTime Length Name`), and `Get-Process` keeps its own columns. The 4/5 boundary belongs to the fallback formatter that handles objects with no registered view.

## F-mixed — two shapes in one stream collapse

```powershell
[pscustomobject]@{ A = 1; B = 2 }
[pscustomobject]@{ X = 9; Y = 8; Z = 7 }
```

```
A B
- -
1 2

```

The second object renders as a blank line: the formatter chose the first shape and the second object has no columns in it. Two objects of the *same* shape only lose the header on the second.

**Fix:** render one shape per call, or emit strings:

```powershell
([pscustomobject]@{ A = 1; B = 2 } | Format-Table -AutoSize | Out-String).Trim()
([pscustomobject]@{ X = 9; Y = 8; Z = 7 } | Format-Table -AutoSize | Out-String).Trim()
```

## F-order — `Format-*` ends the pipeline

```powershell
# broken: sees formatting records, not objects
Get-ChildItem <dir> -File | Format-Table | Where-Object { $_.Length -gt 500 } | Measure-Object
# fixed
Get-ChildItem <dir> -File | Where-Object { $_.Length -gt 500 } | Measure-Object
```

Measured on a directory holding four 600-byte files and one small file: `Measure-Object -Property Length -Sum` reports `Count = 0` and no sum after `Format-Table`, versus `Count = 4, Sum = 2408` when the filter runs first. No error is raised — the result is silently empty, which is the worst failure mode. `Where-Object` after `Format-Table` does not even match: the records it receives carry no `Length` property at all.

Filter, sort, group, and measure first; format last.

## F-enum — collections clip at four items

`$FormatEnumerationLimit` is **4** by default, so a six-item property renders `{t1, t2, t3, t4…}`. Setting `$FormatEnumerationLimit = 20` in the same command renders all six. Join the collection into a string when you need it searchable: `($_.Tags -join ', ')`.

## F-cjk — display width versus character width

`Format-Table` sizes CJK by display cells, so a column of mixed Chinese and ASCII stays aligned:

```
Name     Desc
----     ----
hosts    主机文件
networks 网络配置
```

`'{0,-12}' -f` counts characters, so the same pair misaligns. Use the `-f` recipe only for ASCII output you will grep; use a table for anything containing CJK.

## F-json — three traps

**Depth.** The default is 2. A four-level object serializes as `{"a":{"b":{"c":"@{d=1}"}}}` — the deepest level collapses to its PowerShell string form — *and* emits a warning that is counted by `-WarningVariable` and lands on stdout ahead of the payload. `-Depth 10` gives `{"a":{"b":{"c":{"d":1}}}}` with no warning. Always pass `-Depth`; add `-WarningAction SilentlyContinue` so an unnoticed warning cannot sit in front of the payload.

**Emptiness.** `@() | ConvertTo-Json` produces nothing at all — not `[]`, not an empty string, and `-AsArray` does not change that. A consumer cannot distinguish "no rows" from "the command printed nothing". Branch explicitly:

```powershell
$rows = @(Get-ChildItem -LiteralPath <dir> -File)
if ($rows.Count -eq 0) { '[]' } else { $rows | Select-Object Name, Length | ConvertTo-Json -Depth 5 -Compress }
```

**Single versus array.** One row serializes as an object; `-AsArray` forces `[{...}]` when the consumer expects a list. Pick one convention per call and keep it.

## F-streams — what lands on stdout

| Construct | Lands on |
|---|---|
| `Write-Output`, `Write-Host` | stdout |
| `Write-Warning` | stdout (`警告: ...`) — can precede a JSON payload |
| `Write-Error` | stderr section (`[stderr] Write-Error: ...`) |
| `[Console]::Error.WriteLine` | stderr section |
| `Write-Verbose -Verbose` | stdout (`详细信息: ...`) |
| `Write-Information -InformationAction Continue` | stdout |
| `Write-Progress` | dropped entirely |

Because the two streams are rendered as separate blocks, **interleaved ordering across them is not recoverable**: a `Write-Output 'one'` / stderr write / `Write-Output 'three'` sequence shows `one`, `three`, then the `[stderr]` block. Do not rely on cross-stream order to prove sequencing.

Escape sequences are absent: `$PSStyle.OutputRendering` is `PlainText` and `NO_COLOR=1`, so output is plain text with no ANSI codes to strip.

## F-recipes — copy these

Table, a few rows of a few columns:

```powershell
Get-ChildItem -LiteralPath 'C:\Windows\System32\drivers\etc' -File |
  Select-Object Name, Length, @{ n = 'Modified'; e = { $_.LastWriteTime.ToString('yyyy-MM-dd') } } |
  Format-Table -AutoSize |
  Out-String -Width 200
```

List, one object with several fields:

```powershell
Get-Item -LiteralPath 'C:\Windows\System32\drivers\etc\hosts' |
  Format-List Name, Length, LastWriteTime
```

JSON, for data a later step will consume:

```powershell
Get-ChildItem -LiteralPath 'C:\Windows\System32\drivers\etc' -File |
  Select-Object -First 2 Name, Length |
  ConvertTo-Json -Depth 5 -Compress -WarningAction SilentlyContinue
```

Fixed-width text, for ASCII you will grep:

```powershell
Get-ChildItem -LiteralPath 'C:\Windows\System32\drivers\etc' -File |
  Select-Object -First 3 |
  ForEach-Object { '{0,-14} {1,8}' -f $_.Name, $_.Length }
```

Aggregate before listing:

```powershell
Get-ChildItem -LiteralPath <dir> -File |
  Measure-Object -Property Length -Sum |
  Select-Object Count, @{ n = 'TotalMB'; e = { [math]::Round($_.Sum / 1MB, 1) } } |
  Format-Table -AutoSize |
  Out-String -Width 200
```

Right alignment in a table (only works in `Format-Table`, not in `Select-Object`):

```powershell
Get-ChildItem -LiteralPath <dir> -File |
  Format-Table -Property Name, @{ n = 'Bytes'; e = { $_.Length }; align = 'right' } -AutoSize
```

The same `align` key inside `Select-Object` fails the whole statement with `align 键无效。`.

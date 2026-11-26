# Local environment — facts for this machine

Sampled 2026-11-26 through the `pwsh` tool. This is the only file that is machine-specific: when the environment changes, regenerate it and leave the other files alone.

## PowerShell executable

`@deepseek-ai/dsh-pwsh-local` resolves `pwsh` in this order: `<ProgramFiles>\PowerShell\7\pwsh.exe`, then every `PATH` entry's `pwsh.exe` (which covers Microsoft Store installs), then `<SystemRoot>\System32\WindowsPowerShell\v1.0\powershell.exe` as last resort. When none exists it spawns a bare `pwsh`.

| Fact | Value here |
|---|---|
| Resolved executable | `C:\Users\27314\AppData\Local\Microsoft\WindowsApps\Microsoft.PowerShell_8wekyb3d8bbwe\pwsh.exe` (Store install, found through `PATH`) |
| Version | 7.7.0, PSEdition Core |
| Launch shape | `-NoLogo -NoProfile -NonInteractive -Command <text>` |

Because `-NoProfile` is passed, no profile script runs: nothing defined in a profile (`$PSDefaultParameterValues`, custom modules, `oh-my-posh`) is available. The built-in alias set is still present — 135 aliases here, including `ls`, `cat`, `dir`, `type`, `rm`, `cp`, `mv`, `ps`, `kill`, `ft`, `fl`, `select`, `where`, `%`, and `?`.

## Tool parameters present in this profile

The `standard` preset mounts `@deepseek-ai/dsh-tool-pwsh`, so `pwsh` exposes `command`, `description`, `timeoutMs`, `workdir`, and `run_in_background`. The `minimal` preset instead mounts the persistent `pwsh`, whose only parameter is `command`, and which clips at `maxOutputChars` (default 16 000) with no spill file; if you see that shape, section 0 of the skill applies.

## Executor limits

| Setting | Value |
|---|---|
| Default timeout | 120 000 ms |
| Maximum timeout | 600 000 ms |
| In-memory cap per stream | 64 000 bytes, tail kept, remainder to a spill file |
| Spill cap per stream | 64 MB |

## Console and rendering

| Fact | Value |
|---|---|
| Console handle | none — `[Console]::WindowWidth` throws `IOException: 句柄无效`, stdout is redirected |
| `$Host.UI.RawUI` | reports a virtual 120×9001 buffer and a 120×30 window, stable across calls |
| `Out-String` default width | **120**, from the detached-console fallback; it does not follow `BufferSize` even when a command raises that to 200 |
| `$PSStyle.OutputRendering` | `PlainText` |
| `NO_COLOR` | `1`, injected by `dsh-pwsh-local`'s `ENV_OVERRIDES` |
| ANSI escapes in output | none |
| Line endings | CRLF |

A real console differs on exactly this point: with stdout attached, `Out-String`'s default equals the window width (100, 176, and 200 measured), and it drops back to 120 once that stdout is redirected. The 120 is a property of the tool's detached-console shape, not of PowerShell, which is why the probe reports `SKIP` for its two host checks outside the tool rather than failing them.

## Managed environment

Each call receives a rebuilt `DSH_*` namespace; ambient values are discarded.

| Variable | Meaning |
|---|---|
| `DSH_HOME` | Harness config root, `C:\Users\27314\.dsh` |
| `DSH_SHELL` | `1` |
| `DSH_SESSION_ID` | Current session id |
| `DSH_PROFILE` / `DSH_PROFILE_DIR` | `web` and its directory |
| `DSH_INSTALL_DIR` | Install anchor directory |
| `DSH_NODE_EXECUTABLE` | Node binary backing the harness |
| `DSH_WEB_URL` | Web GUI URL, when the web surface is running |

## Locale

Messages are localized to Chinese. Observed text includes `找不到路径“…”` (path not found), `警告:` (warning), `详细信息:` (verbose), `术语 '…' 不会被识别为…` (command not found), and `在 行:1 字符:28` (position). Never match on message text; use the exit status, the stream a message lands on, and structured properties such as `$_.FullyQualifiedErrorId` (`PathNotFound,...`) or `$_.CategoryInfo.Category` (`ObjectNotFound`).

UTF-8 round-trips correctly for CJK and non-ASCII symbols; the executor pins the console encoding before your command runs.

## Encoding when writing files

`Set-Content` here writes BOM-less UTF-8 by default, and `-Encoding utf8`, `-Encoding utf8NoBOM`, and the default all produced identical bytes for an ASCII payload. Passing `-Encoding utf8` is harmless and self-documenting, not a fix for a real corruption risk on PowerShell 7; the risk exists only on the Windows PowerShell 5.1 fallback, which writes the OEM code page.

## Native argument passing

`$PSNativeCommandArgumentPassing` is `Windows` by default. The default already passes quoted arguments to C-runtime programs correctly; only programs that parse their own command line see a difference between the modes, and `Standard` changes behaviour for them (a self-quoted `cmd /c` call succeeded under `Windows` and failed with a syntax error under `Standard`).

## Tools present

| Tool | Present | Note |
|---|---|---|
| `git` | yes | `F:\Program Files\Git\cmd\git.exe` |
| `node` | yes | provided through `PATH` |
| `curl.exe` | yes | `C:\Windows\system32\curl.exe` — Windows ships it; `curl` resolves to this, not to `Invoke-WebRequest` |
| `rg` (ripgrep) | **no** | use `Select-String` in pwsh, or the `grep` tool |

## Drives and paths

The session workspace is on `D:`, while the harness home and profile live on `C:`. Nothing implies the other drive, so pass absolute paths across drives; `workdir` handles the common case without a `cd`.

## Permission preset

This profile's default permission preset is `danger-full-access` with approval `never`:

- No sandbox confinement is applied, so denial markers and ConstrainedLanguage do not normally appear.
- `sandbox_permissions` escalation cannot succeed — approvals are disabled and the request is rejected. Report a denial rather than escalating.
- Because nothing is confined, filesystem mistakes are not contained. Section 9 of the skill (print the resolved path first) matters more here, not less.

# pwsh-discipline

A DeepSeek Harness skill that makes `pwsh` tool calls readable: how to write the command, and how to shape what comes back.

This directory is the **development source**. It is not the deployment location — DSH loads skills from `$DSH_HOME/skills`, so edit here and deploy, rather than editing the copy DSH reads.

## Layout

| Path | Role |
|---|---|
| `SKILL.md` | The skill body, loaded by the `skill` tool. Frontmatter is `name` + `description` + `whenToUse`. |
| `references/command-authoring.md` | Evidence for the command rules: multi-line bodies, continuation, splatting, the exit-code matrix, `-File` children, native argument modes. |
| `references/output-formatting.md` | Evidence and recipes for rendering: the 120-column width, last-column truncation, `-AutoSize` being inert, Table/List switching, mixed shapes, `Format-*` ending a pipeline, JSON traps, CJK alignment. |
| `references/local-environment.md` | The only machine-specific file: resolved `pwsh` path, alias set, `DSH_*` variables, locale, encoding, argument-passing default. |
| `references/audit-map.md` | Reverse index from probe check id to skill section and evidence row. |
| `references/audit-log.md` | Findings from each audit round, their disposition, and the regression table. |
| `scripts/probe-pwsh-semantics.ps1` | 25 assertions over the exit-code and formatting rules. Prints `PASS`/`FAIL`/`SKIP` per check and always exits 0; `E9` and `E23` are tool-host checks and `SKIP` in a plain terminal. |
| `deploy.ps1` | Validates the frontmatter and copies the skill into `$DSH_HOME/skills`. `-Verify` runs the deployed probe and fails the deploy if it reports any failed check. |
| `AGENTS.md` | Rules for an agent working in this repository: what is non-negotiable, how a rule change moves through the three places it lives. |

## Develop

1. Edit `SKILL.md` or a reference here.
2. If you changed a rule, update its evidence row and, when the rule is machine-checkable, the probe.
3. Run the probe from this directory:

```powershell
& '.\scripts\probe-pwsh-semantics.ps1'
```

It must report `0 failed`. A `FAIL` names the check id; look it up in `references/audit-map.md`.

4. Deploy:

```powershell
.\deploy.ps1
```

The deploy script validates the frontmatter, copies the tree to `$DSH_HOME/skills/pwsh-discipline`, and prints what it wrote. The skill catalog updates on its own — the filesystem provider watches the root and invalidates its cache, so no restart is needed; a session already running sees the new body on its next load.

## Deploy

```powershell
# default target: $DSH_HOME\skills\pwsh-discipline
.\deploy.ps1

# explicit target, and verify afterwards by running the probe from the deployed copy
.\deploy.ps1 -Destination 'C:\Users\you\.dsh\skills\pwsh-discipline' -Verify
```

`-Verify` runs the deployed probe, which is the only step that proves the copy is intact and still matches the environment. It gates on the probe's `summary:` line rather than its exit code, because the probe always exits 0 — that is what stops a red probe from deploying green.

## Constraints

- Run the probe **through the `pwsh` tool** for a full green. Two checks (`E9`, `E23`) assert tool-host facts — the 120-column format width and the `NO_COLOR`/`PlainText` pair — and report `SKIP` in a terminal that has its own width and no DSH environment. Every other check, including `E10`, is host-independent.
- `references/local-environment.md` is machine-specific. Regenerate that one file when the environment changes and leave the others alone.
- The probes here were recorded against DSH 0.2.2-rc.5 with PowerShell 7.7.0. After a DSH or PowerShell upgrade, re-run the probe before trusting the body.

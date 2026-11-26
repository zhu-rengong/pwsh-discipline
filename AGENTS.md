# Working on pwsh-discipline

A DSH skill that keeps `pwsh` tool calls readable. `SKILL.md` is the deliverable; this
repository is its source. Layout and the deploy command are in [README.md](README.md).

## Non-negotiables

- **Never edit the deployed copy.** `$DSH_HOME/skills/pwsh-discipline` is output. Change
  files here, then run `.\deploy.ps1`.
- **No unevidenced rules.** Every claim in `SKILL.md` is either measured through the
  `pwsh` tool or labelled a preference. If you cannot reproduce it, do not state it as fact.
- **Keep the probe green.** A rule that can be checked belongs in
  `scripts/probe-pwsh-semantics.ps1`. Run it before every commit; `0 failed` is the gate.
  Run it through the `pwsh` tool — two checks assert tool-observed facts and can differ
  in a plain terminal.
- **Respect the context budget.** `SKILL.md` is loaded whole whenever the skill is used,
  so every line is paid on each load. Add a rule only if it changes behaviour; delete one
  that does not.

## Changing a rule

A rule lives in three places: the sentence in `SKILL.md`, the evidence row in
`references/`, and the check in the probe. Move them together — a rule without an
evidence row is unsupported, and a check without a rule is noise.

When DSH or PowerShell is upgraded, run the probe first. It names the rule that broke,
and `references/audit-map.md` maps the check back to its section.

## What not to do

- Do not restate the tool contract. `dsh-tool-pwsh` already tells the model its
  parameters, timeouts, and sandbox markers; repeating them spends tokens for nothing.
- Do not enumerate cmdlets or syntax. Give the principle and one example; an exhaustive
  catalogue makes the skill long and its reader slower.
- Do not add a rule you cannot demonstrate in a single command.

## Evidence

`references/` holds measurements, `SKILL.md` holds conclusions. When an audit disagrees
with a rule, the measurement wins — fix the rule, not the prose defending it.
`references/local-environment.md` is the one machine-specific file: regenerate it when the
environment changes and leave the others alone.

## Commits

One change per commit, carrying the rule, its evidence, and its check. Say which rule
moved and why: `fix: the exit guard must default to failure, not $LASTEXITCODE`.

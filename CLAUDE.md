# Agentic Instructions

Common agentic instructions are in AGENTS.md, imported here:

@AGENTS.md

Only place claude specific agentic instructions in this file.

## Claude Code

- Track work in bd (see AGENTS.md > Work Tracking). The session task list is
  for the current session only; file anything that outlives the session in bd.
- Write superpowers specs and plans under `.dev/docs/superpowers/` (see
  AGENTS.md > The `.dev/` Working Area), not under `docs/`.
- Use `mise run <task>` for builds and tests, not ad hoc command chains.

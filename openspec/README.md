# OpenSpec

## Shared OpenSpec bundle

`html-design` comes from Mission Control's tools CLI, `mission-control-tools`.
`.mise.toml` pins its version. The schema, templates and licenses are managed
snapshots; `openspec/extensions.lock.json` records their digests and the tool
version that wrote them. Keep repository overrides in `openspec/config.yaml` and
`AGENTS.md`.

- Run `mise run openspec:check` to verify the committed file digests, the
  default schema and the pinned tool version.
- Run `mise run openspec:setup` to regenerate the six core agent skills with
  isolated global preferences.
- Run `mise run openspec:verify` before review. It runs `openspec:check` and
  `openspec:validate` (`openspec schema validate html-design`, then
  `openspec validate --all --strict`).
- New designs are offline `design.html` with inline CSS. Existing changes keep
  their schema metadata and original designs, including Markdown designs.
- OpenSpec requirements and change artifacts are committed project documentation.
  Scratch documents remain local under the existing repository rules.

To update the snapshots, change the `github:moonrockz/mission-control` version
in `.mise.toml`, then run:

```shell
mise install
mise exec -- mission-control-tools openspec install
mise run openspec:verify
```

See [the tools guide](https://github.com/moonrockz/mission-control/blob/main/apps/tools/README.md).

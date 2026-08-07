# Storage inventory and budgets

`agent-storage-inventory` measures the staged HOME payload without following
symlinks and classifies every entry using
`config/home-template-ownership.json`. Its JSON output is deterministic for an
unchanged tree and records:

- apparent and allocated bytes;
- regular-file, directory, symlink, and other-entry counts;
- totals by ownership class;
- totals for each configured path;
- the status of the selected budget.

The output path must be outside the measured root so writing a prior report cannot
silently change the next measurement.

The image build writes its report to:

```text
/usr/share/agent-sandbox/home-template-inventory.json
```

The staged template is the payload copied into an empty persistent HOME, so its
apparent-byte total is also the initial empty-HOME payload before construct-owned
state begins growing. CI reports that total alongside the locally loaded image
size for pull requests.

## Ownership classes

- `image-owned-software`: runtime or tool installations that should ultimately
  move out of persistent HOME.
- `image-owned-default`: image-provided configuration eligible for versioned
  migration.
- `construct-owned-state`: identity, configuration, transcripts, workspaces, and
  other state that an image upgrade must not silently replace.
- `runtime-cache`: reproducible cache data that needs a retention policy.
- `unclassified`: an attractive-nuisance signal. New top-level paths remain
  visible until their owner is chosen.

Longest matching paths win. For example, `.config/starship.toml` is an
image-owned default while the broader `.config` tree is construct-owned state.
Likewise, Claude's native versioned executable under
`.local/share/claude/versions` is image-owned software while other
`.local/share` data remains construct-owned.

## Budget lifecycle

`config/storage-budgets.json` contains the measurements the seat contract needs.
All ceilings are initially `null`. A null ceiling reports evidence and cannot
fail the build.

After Selene supplies a baseline and safe host headroom, ratify numeric values in
a separate review. The image build currently enforces
`home_template_apparent_bytes`: `agent-storage-inventory` exits with status 2 when
that configured `max_bytes` value is exceeded; configuration or I/O errors use
status 1. The other measurements are explicit placeholders until their runtime
measurement and enforcement paths are ratified.

No Docker or Podman command is required to test the inventory logic:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

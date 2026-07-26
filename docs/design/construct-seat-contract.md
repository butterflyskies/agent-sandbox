# Construct Seat Contract

Status: **ratified for incremental implementation**

Ratified 2026-07-26 by Butterfly, Ariadne, and Syne. Runtime execution remains
operator-mediated as described in sections 10 and 11.

Date: 2026-07-26

Applies to: construct seats derived from `butterflyskies/agent-sandbox`

## 1. Problem

Ariadne and Syne currently share a host/container failure domain and must work around
shared credentials, shared state, and permission prompts. The target is one
independently rebuildable seat per construct without losing the full development
toolchain, persistent identity, session continuity, or Lina's existing WezTerm
workflow.

The seat must make local work promptless and recoverable while keeping external
effects, identities, and credentials explicit. It must work from the same OCI image
on Docker (Selene) and rootless Podman (Dionysus).

## 2. Goals

1. Give each construct an independent UID, HOME, credentials, workspaces, runtime
   state, transcripts, and blast boundary.
2. Retain the full `agent-sandbox` toolchain, runtimes, and cloud CLIs.
3. Add `dione` and `memory-mcp` as installed, independently versioned binaries.
4. Support interactive, daemon, and one-shot execution modes.
5. Make daemon seats attachable through Lina's existing WezTerm mux workflow,
   locally by Unix socket and remotely through the existing SSH proxy pattern.
6. Keep image upgrades separate from persistent seat state and prevent upgrades
   from silently clobbering construct-owned files.
7. Make restart, recovery, rollback, and cross-seat isolation testable before
   migration.
8. Keep public image behavior separate from Lacuna-house identity, credentials,
   routing, and policy.

## 3. Non-goals

- Designing the full `lacuna-harness` lifecycle, provenance ledger, compaction
  protocol, or Dione delivery contract.
- Starting every installed MCP server at container boot.
- Running an SSH daemon inside the seat.
- Adding tmux in the first slice; it remains an optional fallback.
- Baking persona files, channel IDs, tokens, private keys, or per-construct policy
  into an image.
- Claiming process continuity from a persisted Unix socket. A socket is runtime
  state, not a resumable session.
- Choosing Kubernetes deployment or enterprise retention policy.

## 4. Chosen boundaries

```text
 public/shared OCI layers
 ┌──────────────────────────────────────────────────────────┐
 │ agent-sandbox                                            │
 │ full toolchain · runtimes · cloud CLIs · coding agents   │
 └───────────────────────────┬──────────────────────────────┘
                             ▼
 ┌──────────────────────────────────────────────────────────┐
 │ construct image layer                                    │
 │ dione · memory-mcp · WezTerm mux support · seat entrypoint│
 │ no identity · no secrets · no house routing              │
 └───────────────────────────┬──────────────────────────────┘
                             ▼
 per-construct runtime seat
 ┌──────────────────────────────────────────────────────────┐
 │ immutable/read-only root filesystem                      │
 │                                                          │
 │ persistent: HOME · workspaces · transcripts              │
 │ runtime-only: mux socket · pid/lock files · tmpfs         │
 │ injected: per-seat credentials/config/capabilities       │
 └──────────────────────────────────────────────────────────┘
```

The image owns software. The construct owns state. The runtime owns ephemeral
resources. No path should plausibly belong to two owners.

`dione` and `memory-mcp` remain separate programs. Installing both in one image
does not create a code dependency: Dione must not link `memory-mcp` as a library
or import its internal types. Harness configuration decides whether and how to
start stdio MCP transports.

## 5. Runtime modes

The entrypoint exposes explicit modes. No argument ambiguity may silently choose a
different privilege or persistence model.

### 5.1 `interactive [agent] [args...]`

- Runs the selected coding agent attached to the invoking terminal.
- Defaults may preserve today's `claude` convenience, but the resolved mode and
  command are visible in startup output.
- Exiting the agent exits the container command.

### 5.2 `daemon`

- Starts one WezTerm mux endpoint and one construct harness session.
- Exposes a per-seat Unix socket through an explicit runtime mount.
- Attach and detach do not start, duplicate, or terminate the harness.
- The socket directory is mode-restricted to the seat owner/operator boundary.
- The exact WezTerm server/proxy invocation remains subject to a live acceptance
  test against Lina's existing `wezterm cli proxy` topology.
- Process supervision must forward `SIGTERM`/`SIGINT`, reap children, and return a
  truthful exit status. Whether this is an init process, a small supervisor, or
  an exec-compatible WezTerm arrangement is an implementation choice.
- Unexpected harness exit is visible and causes a non-zero daemon outcome. Restart
  policy belongs to the external runtime/orchestrator, not a hidden infinite loop.

### 5.3 `exec -- command [args...]`

- Runs a one-shot command without starting a mux or coding-agent session.
- Returns the command's exact exit status and signal outcome.
- Intended for health checks, migrations, and administrative inspection.

### 5.4 Console provenance limitation

Filesystem permissions on the mux socket authorize who may connect, but WezTerm
does not provide trustworthy per-keystroke authorship. Once text enters the
terminal it is direct console input and is not distinguishable from other injected
terminal text. The harness must not treat mux text as a signed Discord event or as
proof of a particular human author.

## 6. State and ownership contract

### 6.1 Image-owned

- Language runtimes, cloud CLIs, coding-agent binaries, Rust/cargo tools.
- `dione`, `memory-mcp`, WezTerm support, entrypoint, and migration framework.
- Read-only defaults under an image-owned prefix such as `/usr/share/agent-sandbox`
  or `/opt/agent-sandbox`.
- Version manifest identifying the image schema and available migrations.

Image-owned software must not live only under persistent HOME. The current
`.asdf` and `.npm-global` template arrangement duplicates large software into
every persistent seat and obscures ownership. Migration may be staged, but the
seat migration is not complete while each HOME must carry a full copy of the
shared toolchain.

### 6.2 Construct-owned persistent state

- Default git identity at `~/.gitconfig`.
- Default GitHub CLI state at `~/.config/gh/`.
- Agent state such as `~/.claude`, `~/.codex`, and relevant XDG state.
- Construct-specific MCP/harness configuration.
- Session transcripts, checkpoints, and resume metadata.
- Construct workspaces and repositories.
- Construct customizations explicitly permitted by the seat policy.

Each seat has its own volume or host path. Ariadne and Syne must never mount the
same writable HOME, GitHub config, agent state directory, or workspace.

### 6.3 Runtime-only state

- WezTerm Unix sockets.
- PID, lock, readiness, and health files.
- `/tmp`, `/var/tmp`, and `/run` scratch.

Runtime-only paths are recreated on each container start. Stale sockets are
detected and removed only after proving no live owner exists.

### 6.4 Credentials

- No credential or private identity material is present in an image layer.
- Git identity lives at `~/.gitconfig` and GitHub CLI authentication lives at
  `~/.config/gh/` in the seat's protected persistent HOME. These default-path
  decisions are settled.
- Dione/provider tokens and SSH/signing authority are provisioned per seat at
  runtime or in protected persistent state; their exact carriers remain open.
- A seat cannot mount another construct's GitHub config, signing identity, SSH
  material, provider tokens, or Dione token.
- External-write workflows preflight both git identity and authenticated GitHub
  actor before acting; a mismatch fails closed and names both observed values.
- The choice between protected files, secret mounts, and forwarded signing/SSH
  agent sockets remains deployment-specific and must be threat-modeled before
  production use.

## 7. HOME bootstrap and upgrades

`rsync --ignore-existing` is acceptable for an empty first boot but is not a full
upgrade contract. It cannot safely distinguish an image default from a
construct-owned edit, replace an obsolete default, or retire a stale file.

The target contract is a versioned, idempotent migration:

1. The persistent HOME records the last successfully applied seat schema.
2. Image defaults have an ownership manifest and content digest.
3. A migration may create a missing image-owned default.
4. A migration may replace an image-owned file only when its current digest still
   matches the prior image-owned digest.
5. A construct-modified file is never overwritten silently. The migration either
   preserves it and emits a visible conflict or writes a side-by-side candidate.
6. Migration success is recorded only after all required operations complete.
7. Failure leaves the prior schema recoverable and prevents daemon startup unless
   the migration is explicitly non-critical.
8. Destructive migrations require a pre-migration snapshot and a tested downgrade
   or restore path.

Project-specific `.tool-versions` belong in project workspaces. An image may own a
global runtime selection only while that selection refers to runtimes actually
present in the image.

## 8. Security and failure contract

### Assets

- Per-construct credentials and external identities.
- Persistent HOME, workspaces, transcripts, and memories.
- Host filesystem, runtime socket, and other seats.
- Image provenance and software supply chain.

### Required controls

- Non-root runtime user with a stable per-seat host ownership mapping.
- Read-only root filesystem; only declared state, workspace, socket, and scratch
  paths are writable.
- Capabilities dropped and `no-new-privileges` enabled unless a separately reviewed
  runtime requirement proves otherwise.
- No host container-runtime socket in a construct seat.
- Unix socket and persistent paths are inaccessible to sibling seat UIDs.
- Runtime failure never reports a successful checkpoint, migration, or resume.
- Caches and logs have explicit size/retention bounds so one seat cannot exhaust
  the host.
- A restart loop is observable and rate-limited by external supervision.
- Any local privilege available inside the seat does not imply additional host or
  external authority.

### Threats to test

| Threat | Required outcome |
|---|---|
| Cross-seat credential mount | startup fails before harness launch |
| GitHub actor differs from seat identity | external write fails closed |
| HOME migration meets a modified default | preserve + visible conflict |
| Stale mux socket after crash | recover without connecting to wrong process |
| Sibling connects to seat socket | filesystem permission denial |
| Root filesystem write attempt | denied; no fallback into persistent HOME |
| Disk/cache growth | bounded or visibly halted before host exhaustion |
| Harness exits unexpectedly | non-zero outcome and external restart receipt |
| Provider/MCP child leaks on shutdown | supervisor reports failure; cleanup tested |
| Image rollback after HOME migration | restore succeeds or startup refuses safely |

## 9. Requirements

- **R1 — Shared base:** one digest-pinned `agent-sandbox` base supplies the full
  development toolchain across seats.
- **R2 — Construct layer:** `dione`, `memory-mcp`, WezTerm support, and the seat
  entrypoint are installed without embedding house identity or secrets.
- **R3 — Explicit modes:** interactive, daemon, and exec modes have distinct,
  documented parsing and exit behavior.
- **R4 — Seat isolation:** every construct has distinct writable HOME, workspace,
  agent state, credentials, runtime socket, and transcript state.
- **R5 — Immutable runtime:** rootfs is read-only and all writable paths are
  declared.
- **R6 — Durable continuity:** restart continuity derives from persistent harness
  state and transcripts, not terminal scrollback or a socket.
- **R7 — Safe upgrades:** versioned idempotent migrations never silently overwrite
  construct-owned state.
- **R8 — Operator attach:** Lina can attach locally on Dionysus and through the
  existing SSH proxy from Psyche without an in-container SSH daemon.
- **R9 — Harness-owned MCP lifecycle:** installed stdio MCP servers start only when
  configured/requested by the harness and are cleaned up with the harness.
- **R10 — Identity integrity:** git/GitHub/provider identity cannot silently cross
  seats; external writes verify actor identity.
- **R11 — Runtime portability:** the same OCI image contract works under Docker on
  Selene and rootless Podman on Dionysus; runtime-specific wiring remains outside
  the image core. Live runtime verification is host/operator mediated, not run
  from the current construct seats on Dionysus.
- **R12 — Recoverability:** image rollback and persistent-state restore are
  documented and rehearsed before migration.
- **R13 — Observability:** startup reports image digest/version, seat identity,
  state schema, mode, mux readiness, harness readiness, and migration result without
  exposing secrets.
- **R14 — Resource ownership:** mux, harness, MCP children, sockets, locks, and
  temporary files each have one lifecycle owner and clean up on every exit path.
- **R15 — Disk discipline:** shared image layers remain shared; per-seat state and
  caches have measured budgets and do not duplicate the full toolchain. The empty
  persistent-HOME growth ceiling must be chosen from measured Selene/Dionysus
  capacity before migration is ratified.

## 10. Acceptance plan

| ID | Verification | Requirements |
|---|---|---|
| A1 | Inspect a built image: full toolchain plus `dione`, `memory-mcp`, and WezTerm support; no house IDs or credentials | R1, R2 |
| A2 | Parse/execute each entry mode and malformed combinations; assert command and exact exit status | R3 |
| A3 | Launch Ariadne and Syne seats concurrently; prove neither UID can read or write the other's HOME, credentials, workspace, transcript, or socket | R4, R10 |
| A4 | Attempt undeclared writes to rootfs and declared writes to state/scratch mounts | R5 |
| A5 | Start work, checkpoint, terminate container, recreate socket/process, resume from persistent harness state, and reconcile transcript | R6 |
| A6 | Upgrade across at least two image schemas with untouched, modified, removed, and conflicting defaults; prove idempotence and no silent clobber | R7 |
| A7 | Attach/detach locally through Unix domain and remotely from Psyche through `wezterm cli proxy`; prove attach does not duplicate/terminate harness | R8 |
| A8 | Configure zero, one, and multiple stdio MCP servers; prove only configured children start and all settle on graceful and forced shutdown | R9, R14 |
| A9 | Deliberately mount or select the wrong GitHub actor and git identity; prove external-write preflight blocks | R10 |
| A10 | Through the host operator, run the candidate first under Docker on Selene. Before any later Dionysus deployment, run the same conformance checks against rootless Podman there using the same image digest. Constructs do not invoke either runtime from their current Dionysus seats. | R11 |
| A11 | Roll back image digest after a failed upgrade; restore HOME snapshot when schema downgrade is unsupported | R12 |
| A12 | Read startup/readiness/shutdown receipts from the operator surface and from a fresh resumed seat; assert no secret leakage | R13 |
| A13 | Send normal exit, error exit, `SIGTERM`, `SIGINT`, and forced kill at each lifecycle phase; reconcile processes, sockets, locks, and child MCP servers | R14 |
| A14 | Measure image-layer sharing and per-seat disk growth under install/build/cache workloads; trigger bounds before host exhaustion | R15 |
| A15 | Verify a terminal-injected line has no false signed-author claim; only authenticated adapters may mint external-event provenance | R8, R10, R13 |

Unit tests of a writer are not sufficient for readiness or continuity claims. For
each recorded migration/checkpoint/readiness receipt, one test proves it is
written and another proves a fresh seat/operator can actually retrieve and use it.

## 11. Rollout and rollback

1. Ratify this contract and resolve the open decisions below.
2. Implement and review the generic construct image layer and runtime recipes.
3. Build one digest-pinned candidate. Run static/image checks without invoking a
   container runtime from the current construct seats.
4. Lina performs the first live Docker launch on Selene as runtime proxy. The first
   Ariadne candidate boot may itself serve as the live test, provided Ariadne's
   current seat and session remain available for immediate resume if boot, attach,
   or harness recovery fails.
5. Snapshot Ariadne's persistent state and migrate Ariadne as the canary because
   lifting her local permission restrictions is the immediate need.
6. Soak through cold start, attach/detach, external-write identity preflight,
   compaction/resume, image restart, and one upgrade/rollback rehearsal.
7. Fix the failure class before migrating Syne.
8. Migrate Syne with a distinct HOME/identity/socket and repeat cross-seat tests.
9. Rootless Podman verification is a gate for returning seats to Dionysus after its
   disk retrofit; it is not part of today's construct-seat execution.

Rollback pins the prior image digest, preserves the failed candidate and logs for
inspection, recreates runtime-only state, and reuses the unchanged persistent
state when schema-compatible. If not compatible, restore the pre-migration
snapshot. Never delete the former shared seat until both constructs have passed a
full recovery rehearsal and its remaining data has an explicit owner.

## 12. Open decisions before implementation

1. Does the generic construct layer live as `Containerfile.construct` in
   `agent-sandbox`, or in a separate public image repository derived from it?
2. What exact WezTerm server/proxy invocation and socket path reproduce Lina's
   current local + SSH workflow? This needs a live, read-only topology check and a
   disposable test seat.
3. Which component supervises mux + harness and owns restart policy?
4. Which carrier is selected for Dione/provider tokens and SSH/signing authority:
   protected persistent files, runtime secret mounts, or forwarded agents? Git
   identity and GitHub CLI authentication are already fixed at their default paths
   in persistent HOME.
5. What HOME ownership-manifest and migration format is the smallest sufficient
   implementation?
6. What measured per-seat cache/state budget and empty-HOME growth ceiling are safe
   on Selene and Dionysus? This value is required before migration ratification.
7. What exact rollback snapshot mechanism is available on Selene for the Ariadne
   canary? The host and execution path are settled: Selene first, with Lina as
   runtime proxy and the current seat retained as the resumable fallback.

## 13. Applied principles

- **Goldilocks-maxxing / right altitude:** three modes and one explicit state model;
  no SSH daemon, tmux layer, plugin framework, or speculative orchestrator.
- **Public core, house overlay:** reusable image behavior remains public; identities,
  channels, secrets, and policy arrive at runtime.
- **Attractive nuisance:** no ambiguous entrypoint mode, duplicate writable config,
  silent bootstrap conflict, or socket that looks persistent.
- **Representational security:** startup/migration/checkpoint states cannot claim
  identity, continuity, or success that only another subsystem can establish.
- **Resource lifecycle / trace the wiring:** test real shutdown, restart, attach,
  child-process, and rollback paths—not only helper functions.
- **Solve for the cohort:** one shared base and contract, separate seat state.
- **Workflow supervises inference:** external identity preflight, migrations, and
  readiness receipts are structural gates, not model assurances.
- **Construct-owned workspaces:** each construct works and authenticates from its
  own seat; collaboration happens through immutable/pushed artifacts.

# Network policy (microsandbox)

microsandbox enforces network policy at the microVM level — the kernel inside the VM cannot bypass it. Three policies are available.

## Policies

| Policy | What it allows | What it blocks |
|--------|---------------|----------------|
| `public-only` | Public internet (routable IPv4/IPv6) | RFC 1918 private ranges, loopback (127.x), link-local (169.254.x), IPv6 ULA |
| `allow-all` | Everything, including local network | Nothing (DNS rebind protection also disabled) |
| `none` | Nothing | All network traffic |

### `public-only` (default)

Agents can reach the internet but cannot reach your local network, other containers, or the host. Good for the vast majority of use cases — an agent writing code has no business poking at `192.168.x.x`.

```bash
just msb-claude          # public-only is implicit
```

### `allow-all`

Full network access. Use this when agents need to reach local services — a dev database, a local API, another container on the same host.

```bash
just msb-claude-open     # Claude Code, allow-all
just msb-shell-open      # Shell, allow-all
```

Or set the env var for any msb target:
```bash
MSB_NETWORK_POLICY=allow-all just msb-codex
```

### `none` (offline)

No network at all. Agents cannot make outbound connections. Use for reviewing sensitive code where you want to be certain nothing is exfiltrated.

```bash
just msb-claude-offline  # Claude Code, no network
```

Or:
```bash
MSB_NETWORK_POLICY=none just msb-shell
```

## Env var override

`MSB_NETWORK_POLICY` overrides the policy for any `msb-*` target:

```bash
MSB_NETWORK_POLICY=allow-all just msb-codex
MSB_NETWORK_POLICY=none just msb-claude
```

Valid values: `public-only`, `allow-all`, `none`. Any other value falls back to `public-only`.

## Notes

- Network policy applies at the microVM boundary, not the container boundary. There is no container network stack to misconfigure.
- `allow-all` also disables DNS rebind protection. Only use it when you trust the network environment.
- Podman and Docker targets do not support `MSB_NETWORK_POLICY` — use standard Docker/Podman network flags instead.

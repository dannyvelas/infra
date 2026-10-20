# Interface Contract: Vultr Server Provisioning Automation

This module exposes no network API — its interface is the Terraform variable (input) and output contract the operator interacts with via `terraform apply`. This document is the contract future implementation must satisfy; it is not the `.tf` source itself.

## Input contract (`variables.tf`)

| Variable | Type | Required | Default | Satisfies |
|---|---|---|---|---|
| `label` | string | yes | — | FR-004, FR-018 (unique per server; also the state/workspace key) |
| `region` | string | no | documented default region code | FR-004 |
| `plan` | string | no | documented default plan/size code | FR-004 |
| `os_id` | number | no | documented default Debian OS image ID | FR-004 |
| `admin_username` | string | no | `admin` | FR-007 |
| `ssh_port` | number | no | documented non-standard default port | FR-012 |
| `allowed_ports` | list(number) | no | `[]` | FR-011 |
| `update_notification_email` | string | no | placeholder requiring override | FR-016 |
| `update_reboot_time` | string (`HH:MM`) | no | `04:00` | FR-016 |

**Contract rules**:
- A run MUST fail validation before any cloud resource is touched if `label` is empty, or if `ssh_port`/any entry in `allowed_ports` is outside the valid TCP port range.
- A run targeting a `label` for which local Terraform state already shows a fully-provisioned server MUST be a no-op (idempotent), per FR-018.
- No variable in this contract may accept secret material (passphrases, passwords) as input — those are always generated, never supplied, per FR-002/FR-008.

## Output contract (`outputs.tf`, satisfies FR-017)

Emitted once a run completes successfully:

| Output | Type | Description |
|---|---|---|
| `label` | string | Echoes the input label, for operator cross-reference. |
| `ip_address` | string | The instance's network address. |
| `admin_username` | string | The administrative account's username. |
| `ssh_port` | number | The port the operator must use for all subsequent `ssh`/`scp` commands. |

**Contract rules**:
- This output set MUST be sufficient, on its own, for the operator to connect to the server without reading any script source or Terraform internals (FR-017).
- This output set MUST NOT include the SSH key passphrase or the console-recovery password — those are satisfied by the one-time terminal print described in FR-008 and research.md §3, not by a persisted Terraform output.

## Failure contract

| Condition | Required behavior |
|---|---|
| Instance never reaches `active` state (Edge Case) | `apply` halts with a non-zero exit after a documented timeout, rather than hanging indefinitely or proceeding against a non-existent IP. |
| cloud-init never reports completion, or reports a failed module (Edge Case) | `apply` halts with a non-zero exit after a documented timeout, before any verification or lock-down step runs; the instance is left exactly as cloud-init left it (dual-port SSH, root login and password auth still enabled). |
| Admin key/sudo verification fails (FR-009) | `apply` halts with a non-zero exit before any further hardening step runs; root access, password auth, and port 22 remain exactly as cloud-init set them up. |
| New-SSH-port verification fails (FR-013) | `apply` halts with a non-zero exit before root login / password authentication are disabled and before the port-22 fallback rule is removed. |
| `label` collides with an existing resource (FR-018) | `apply` halts with a non-zero exit before any resource is created or modified. |

In every failure case above, the halted run MUST leave the server (if one exists yet) at least as accessible as it was before that step started — never in a state reachable by neither the original root path nor the new administrative path.

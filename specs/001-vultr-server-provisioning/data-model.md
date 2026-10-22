# Phase 1 Data Model: Vultr Server Provisioning Automation

These are the entities introduced in [spec.md](./spec.md), expressed as the concrete fields each will carry as Terraform variables/resource attributes or script-local values. No implementation code — this documents shape and validation rules only; see `contracts/` for the operator-facing interface.

## Server Instance

Represents the provisioned cloud server.

| Field | Source | Validation / Notes |
|---|---|---|
| `label` | operator input (required) | Must be unique per FR-017; used as the Terraform state/workspace key (research.md §5). |
| `region` | operator input (optional) | Defaults to a documented region code if unspecified (FR-004). |
| `plan` | operator input (optional) | Defaults to a documented plan/size code if unspecified (FR-004). |
| `os_id` | operator input (optional) | Defaults to a documented Debian OS image ID if unspecified (FR-004). |
| `ssh_key_id` | derived | Set from the SSH Key Pair's registered public-key ID; wired into instance creation (FR-005). |
| `ip_address` | derived (resource output) | Not known until the instance reaches `active` (FR-006); used by every subsequent script. |
| `state` | derived (resource output) | `pending` → `active`; scripts must not run until `active` and `ip_address` is present. |

## SSH Key Pair

The dedicated per-server credential generated in Step 1 of the original runbook.

| Field | Source | Validation / Notes |
|---|---|---|
| `private_key_path` | generated locally | One key pair per `label`, never reused across labels (FR-001); lives under the operator's local `~/.ssh/`, outside Terraform state. |
| `public_key_content` | generated locally | The only part registered with the provider (`vultr_ssh_key`); safe to persist in Terraform state since it is not secret. |
| `passphrase` | generated locally, operator-supplied at generation time | Never written to state/logs/repo (FR-002); handed to the operator via the one-time terminal print described in FR-008. |
| `comment` | derived | `admin@<label>`, mirroring the runbook's `-C` convention, for identification only. |

## Administrative Account

The non-root user created on a Server Instance in Step 3.

| Field | Source | Validation / Notes |
|---|---|---|
| `username` | operator input (optional) | Defaults to `admin`, matching the runbook. |
| `authorized_key` | applied by cloud-init at first boot | Set to the SSH Key Pair's public key for this server only; templated into `user_data`, which is not secret. |
| `sudo_policy` | fixed, applied by cloud-init | Always passwordless (`NOPASSWD:ALL`) per FR-007 — this is not operator-configurable, matching the runbook's explicit requirement. |
| `console_recovery_password` | generated on the instance by cloud-init's `runcmd`, never templated into `user_data` | Console-recovery use only (FR-008); retrieved and printed exactly once by `fetch-recovery-password.sh` after FR-009 passes, then deleted from the instance — never passes through Terraform state (research.md §3). Never valid over SSH once password authentication is disabled (FR-013). |
| `verified` | derived (script result) | Set `true` only after `verify-admin-access.sh` confirms the admin account is reachable on `ssh_port` with its key and can use sudo without a password prompt (FR-009); gates `lockdown-ssh.sh`. A successful check is itself proof cloud-init has finished — no separate "cloud-init done" signal is tracked. |

## Hardening Configuration

The SSH/firewall posture applied to a Server Instance in Step 4.

| Field | Source | Validation / Notes |
|---|---|---|
| `ssh_port` | operator input (optional) | Defaults to a documented non-standard port; `22` is a valid value with no special handling (FR-012). Templated into the cloud-init bootstrap config and the firewall rule for this port — must be used consistently by the operator's own future `ssh`/`scp` commands, mirroring the runbook's own caution. |
| `allowed_ports` | operator input (optional) | Additional inbound ports beyond `ssh_port` the operator designates for the server's workload (FR-011); empty by default; each becomes a permanent `vultr_firewall_rule` on the firewall group. |
| `root_login_enabled` | derived (instance state) | Starts `true` (set by cloud-init), flips to `false` only after Administrative Account's `verified` is `true`, by `lockdown-ssh.sh`, within the same run that provisioned the server (FR-013). |
| `password_auth_enabled` | derived (instance state) | Starts `true` (set by cloud-init), flips to `false` at the same point as `root_login_enabled` (FR-013). |

## Update Policy

The automatic-update behavior applied to a Server Instance in Step 5.

| Field | Source | Validation / Notes |
|---|---|---|
| `notification_email` | operator input (optional), applied by cloud-init | Defaults to a placeholder the operator is expected to override (FR-015); used only for the local `unattended-upgrades` mail setting, with no outbound relay implied (see spec Assumptions). Not secret — safe to template into `user_data`/state. |
| `reboot_time` | operator input (optional), applied by cloud-init | Defaults to an off-hours time (e.g. `04:00`) outside typical working hours (FR-015). |
| `automatic_reboot` | fixed, applied by cloud-init | Always enabled per FR-014 — not operator-configurable, matching the runbook's explicit requirement. |

## Relationships

- One **SSH Key Pair** belongs to exactly one **Server Instance** and exactly one **Administrative Account** (1:1:1, enforced by FR-001).
- One **Server Instance** has exactly one **Administrative Account**, one **Hardening Configuration**, and one **Update Policy** (1:1:1:1) — this feature does not model multiple admin accounts or multiple concurrent hardening profiles per server.
- **Hardening Configuration**'s `root_login_enabled` and `password_auth_enabled` are state transitions, not independent inputs: their *initial* values are set unattended by cloud-init at first boot, and they are only ever flipped to their locked-down values — gated by Administrative Account's `verified` field — in the order described in FR-009/FR-010/FR-013/FR-018, within the same run, never set directly by operator input.
- **Administrative Account**'s `console_recovery_password` is the one field in this model that intentionally never appears in any Terraform-managed attribute (not `user_data`, not an output) — it exists only on the instance's disk (briefly) and in the operator's terminal/secret storage, per research.md §3.

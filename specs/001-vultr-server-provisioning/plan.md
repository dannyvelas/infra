# Implementation Plan: Vultr Server Provisioning Automation

**Branch**: `001-vultr-server-provisioning` | **Date**: 2026-10-18 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-vultr-server-provisioning/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Replace the manual, multi-terminal Vultr provisioning runbook with a Terraform root module (using the official `vultr/vultr` provider) that creates the dedicated SSH key, a Vultr Firewall Group, and the instance itself. The feature splits cleanly along the one place the runbook truly needs an outside observer: everything that's a one-shot, unconditional boot-time action (admin account creation, package installs, SSH on the configured port, automatic-update configuration) is done declaratively via **cloud-init** (`user_data`), while the verify → lock-down gate (confirm admin/key access works, *then* disable root login/password auth) runs as a short ordered chain of scripts invoked via `local-exec` provisioners. Terraform's fail-fast provisioner behavior is used directly as the "halt on verification failure, don't disable root/password login" safety mechanism required by User Story 2, so no separate orchestration engine is needed, and no SSH session is opened at all for the parts of the runbook that don't need one. The firewall group has no special handling for port 22 — it's just whichever port the operator configures.

## Technical Context

**Language/Version**: Terraform >= 1.5 (HCL) for resource declaration; POSIX-compatible Bash (matching the original runbook's shell commands) for provisioner scripts.

**Primary Dependencies**: `vultr/vultr` Terraform provider (SSH key, firewall group/rules, and instance resources, including the `user_data` field that carries the rendered cloud-init config); cloud-init (already present on the stock Debian cloud image Vultr boots — no new dependency to install) for unattended bootstrap; OpenSSH client tools (`ssh-keygen`, `ssh`) invoked from local-exec provisioners for the verify/lock-down gate only; target-instance packages installed by cloud-init itself (`unattended-upgrades`, `apt-listchanges`, `bsd-mailx`).

**Storage**: Terraform state file only (local backend by default, excluded from version control); no application database. Generated secrets (SSH key passphrase, admin console-recovery password) are deliberately never written to state, scripts' own files, or version control — see FR-002/FR-008 and research.md.

**Testing**: `terraform validate` + `terraform fmt -check` for the module; `shellcheck` for provisioner scripts; a documented manual quickstart run against a real (disposable) Vultr instance as the end-to-end acceptance test, since destructive cloud-hardening steps are not suitable for an automated CI pipeline that runs against production-shaped infrastructure.

**Target Platform**: Operator's local workstation (macOS/Linux) running Terraform against the Vultr API; provisioned target is a Debian-based Vultr cloud instance.

**Project Type**: Single-project infrastructure-as-code module (not a library/web/mobile app).

**Performance Goals**: Not throughput-bound; success is measured by SC-004 (a few minutes of operator hands-on time per run, excluding instance boot wait).

**Constraints**: No step may disable root login or disable password authentication unless the preceding verification step has already succeeded (FR-010, FR-018); no generated secret may be persisted in Terraform state, scripts, logs, or version control (FR-002, FR-008).

**Scale/Scope**: One server provisioned per automation run; expected usage is a handful to a few dozen servers managed over time by a single operator, not fleet-scale.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` still contains only unfilled template placeholders — no principles have been ratified for this project yet. There are no constitutional gates to evaluate against this plan. (If the project constitution is ratified later, this feature should be re-checked against it retroactively.)

## Project Structure

### Documentation (this feature)

```text
specs/001-vultr-server-provisioning/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── interface.md     # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
main.tf                      # vultr_ssh_key + vultr_firewall_group/rules + vultr_instance (user_data = rendered cloud-init) + terraform_data verify/lockdown chain
variables.tf                 # label, region, plan, os_id, ssh_port, admin_username, update_notification_email, update_reboot_time, allowed_ports
outputs.tf                   # connection record per FR-016 (label, ip, admin user, ssh port)
versions.tf                  # terraform + vultr provider version constraints

cloud-init/
└── user-data.yaml.tftpl     # FR-007, FR-008 (password generated on-box, never templated in), FR-012, FR-014, FR-015

servers/
└── myserver.tfvars.example  # example per-server variable override (one file per provisioned label)

scripts/
├── generate-ssh-key.sh          # FR-001, FR-002: dedicated keypair, never persisted to state/repo (local, pre-instance)
├── verify-admin-access.sh       # FR-009: admin key auth + passwordless sudo verification gate (retries until cloud-init has finished)
├── fetch-recovery-password.sh   # FR-008: one-time retrieval/print of the on-box-generated password, then deletes it
├── lockdown-ssh.sh              # FR-013: disables root/password auth on sshd_config.d, same port, after verification passes
└── print-connection-info.sh     # FR-016: emits the post-run connection record

tests/
└── validate.sh                 # terraform validate + terraform fmt -check + shellcheck wrapper
```

**Structure Decision**: Single Terraform root module at the repository root (this repo is dedicated to infrastructure-as-code, so no separate `infra/` nesting is needed). One root module handles the full resource + bootstrap + hardening + update lifecycle for one server per `terraform apply`; each server gets its own `servers/<label>.tfvars` file and, per FR-001's "never reuse a key across servers" rule, its own Terraform state (one state file/workspace per label — see research.md §5). The bootstrap half of the runbook (Steps 3 and 5, plus the SSH-port setup half of Step 4) is expressed declaratively as a cloud-init template passed through `user_data`, plus the firewall rules as plain Terraform resources — no SSH session is opened for any of it. Only the verify → lock-down gate (the risky half of Step 4 — disabling root login and password auth) runs as an ordered chain of `local-exec` scripts on a `terraform_data` depending on the instance, so a failing verification script aborts `terraform apply` before that irreversible step runs (research.md §2).

## Complexity Tracking

Not applicable — no constitution exists yet, so there are no gate violations to justify.

## Post-Design Constitution Re-check

Re-checked after Phase 1 design (data-model.md, contracts/interface.md, quickstart.md): unchanged from the pre-research gate — `.specify/memory/constitution.md` is still unratified, so no gates apply. Nothing in the resulting Terraform/script design (secrets handling, per-label state isolation, provisioner-based verification gates) introduces a concern that would need to be revisited if a constitution is ratified later.

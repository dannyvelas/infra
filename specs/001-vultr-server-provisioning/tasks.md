---

description: "Task list template for feature implementation"
---

# Tasks: Vultr Server Provisioning Automation

**Input**: Design documents from `/specs/001-vultr-server-provisioning/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/interface.md, quickstart.md

**Tests**: No automated test suite is used for this feature — research.md §7 documents that decision (the correctness that matters is side effects on real, billed cloud infrastructure and an irreversible SSH lockdown sequence, not unit-testable logic). The quickstart.md manual validation run serves as the acceptance test and is included as explicit tasks within each user story phase below.

**Organization**: Tasks are grouped by user story (spec.md) to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2)
- Every task names the exact file(s) it creates or edits

## Path Conventions

Single Terraform root module at the repository root, per plan.md's Project Structure:

```text
main.tf, variables.tf, outputs.tf, versions.tf
cloud-init/user-data.yaml.tftpl
servers/myserver.tfvars.example
scripts/*.sh
tests/validate.sh
```

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Repository scaffolding and tooling, no resource logic yet

- [ ] T001 Create the repository directory structure: `cloud-init/`, `servers/`, `scripts/`, `tests/`, matching the tree in plan.md's Project Structure
- [ ] T002 [P] Create `versions.tf` pinning `terraform >= 1.5` and the `vultr/vultr` provider (per research.md §1)
- [ ] T003 [P] Create `.gitignore` excluding `*.tfstate`, `*.tfstate.backup`, `.terraform/`, `.terraform.lock.hcl`, and `servers/*.tfvars` (every real per-label tfvars file), while still tracking the committed `servers/myserver.tfvars.example`
- [ ] T004 [P] Create `tests/validate.sh` running, in order: `terraform fmt -check`, `terraform validate`, `shellcheck scripts/*.sh` — exiting non-zero if any step fails (research.md §7)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The shared variable contract both user stories build on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T005 Create `variables.tf` declaring every input from contracts/interface.md's Input contract table: `label` (string, required, no default), `region` (string, optional, documented default region code), `plan` (string, optional, documented default plan/size code), `os_id` (number, optional, documented default Debian OS image ID), `admin_username` (string, optional, default `"admin"`), `ssh_port` (number, optional, documented non-standard default port), `allowed_ports` (list(number), optional, default `[]`), `update_notification_email` (string, optional, default is a placeholder requiring override), `update_reboot_time` (string in `HH:MM` form, optional, default `"04:00"`)
- [ ] T007 [P] Create `servers/myserver.tfvars.example` as the per-label override template described in plan.md's Structure Decision (one tfvars file per provisioned server label; each label gets its own Terraform state per research.md §5)
- [ ] T008 Add `validation` blocks to the `label`, `ssh_port`, and `allowed_ports` variables in `variables.tf`: reject an empty `label`, and reject any `ssh_port` or `allowed_ports` entry outside the valid TCP port range 1–65535, per contracts/interface.md's input contract rules

**Checkpoint**: Foundation ready — user story implementation can now begin

---

## Phase 3: User Story 1 - Provision a new hardened server end-to-end (Priority: P1) 🎯 MVP

**Goal**: A single `terraform apply` takes an operator from "I need a new server" to a fully provisioned, hardened, auto-updating instance, replacing every manual command in the original runbook.

**Independent Test**: Run the automation against a fresh label end-to-end (quickstart.md Steps 1–3) and confirm the resulting server has key-only admin access on the custom port, root/password SSH disabled, firewall default-deny with only the custom port (and any configured `allowed_ports`) open, and automatic updates enabled.

### Implementation for User Story 1

- [ ] T009 [P] [US1] Write `scripts/generate-ssh-key.sh`: given a label, runs `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_<label> -C "admin@<label>"`, generating one dedicated key pair never reused across servers (FR-001); the interactive passphrase prompt and the private key file are never captured, echoed, or copied anywhere else (FR-002)
- [ ] T010 [US1] In `main.tf`, add a `local-exec` provisioner (on a `terraform_data` or `data` source) that runs `scripts/generate-ssh-key.sh` for `var.label` before any Vultr resource, then define a `vultr_ssh_key` resource whose `ssh_key` attribute reads only the generated **public** key content (FR-003) — the private key and passphrase must never be read into any `.tf`-managed attribute
- [ ] T011 [US1] In `main.tf`, define the `vultr_instance` resource using `var.label` as `label`, `var.region` as `region`, `var.plan` as `plan`, `var.os_id` as `os_id`, and `ssh_key_ids = [vultr_ssh_key.admin.id]` from T010, so initial root access requires no emailed or manually-typed password (FR-005)
- [ ] T032 [US1] In `main.tf`, define a `vultr_firewall_group` resource and a `vultr_firewall_rule` for `var.ssh_port` plus one per `var.allowed_ports` entry (no special-casing of port 22 — research.md §9); set `vultr_instance.server`'s `firewall_group_id` to the group's id, amending T011 (FR-011, FR-012)
- [ ] T012 [P] [US1] Create `cloud-init/user-data.yaml.tftpl`: a `users` entry creating `${admin_username}` with the dedicated public key authorized for SSH and passwordless sudo — the sudoers entry must grant exactly `NOPASSWD:ALL` (FR-007) — plus a `packages` list installing `unattended-upgrades`, `apt-listchanges`, `bsd-mailx`; add a `runcmd` entry that generates a random value locally (e.g. via `openssl rand -base64 18`), applies it as `${admin_username}`'s password via `chpasswd`, and writes that same value to a root-owned, `600`-permission file on the instance — the value must never appear anywhere else in this template, so it never enters the rendered `user_data` Terraform persists to state (FR-008, research.md §3)
- [ ] T013 [US1] Extend `cloud-init/user-data.yaml.tftpl`'s `runcmd`: write `/etc/ssh/sshd_config.d/00-admin.conf` containing a single `Port ${ssh_port}` line (no other port — research.md §2, §9); restart whichever of `ssh.service`/`ssh.socket` `systemctl is-active ssh.socket` reports as active (FR-012, research.md §6). Root login and password authentication are left at their defaults (enabled) here — disabling them happens later, after verification.
- [ ] T014 [US1] Extend `cloud-init/user-data.yaml.tftpl`'s `runcmd`: write `/etc/apt/apt.conf.d/20auto-upgrades` with `APT::Periodic::Update-Package-Lists "1";` and `APT::Periodic::Unattended-Upgrade "1";`; write `/etc/apt/apt.conf.d/51custom-unattended-upgrades` setting `Unattended-Upgrade::Mail` to `${update_notification_email}`, `Unattended-Upgrade::Remove-Unused-Kernel-Packages "true"`, `Unattended-Upgrade::Remove-Unused-Dependencies "true"`, `Unattended-Upgrade::Automatic-Reboot "true"`, and `Unattended-Upgrade::Automatic-Reboot-Time` to `${update_reboot_time}`; then `systemctl enable --now unattended-upgrades` (FR-014, FR-015)
- [ ] T015 [US1] In `main.tf`, set the `vultr_instance` resource's `user_data` to `templatefile("cloud-init/user-data.yaml.tftpl", {...})`, passing `admin_username`, the T010 public key, `ssh_port`, `update_notification_email`, and `update_reboot_time` from the corresponding variables (FR-006: the instance isn't considered ready for the next phase until it reaches `active` with this `user_data` applied)
- [ ] T017 [P] [US1] Write `scripts/verify-admin-access.sh`: retries, with a bounded timeout, `ssh -p ${ssh_port}` as `${admin_username}` with the dedicated key running `id; sudo whoami`; exits `0` only once `id` shows the admin account in the `sudo` group and `sudo whoami` prints `root` with no password prompt (FR-009). No connection can succeed until cloud-init has finished, so this single retry loop also covers "wait for cloud-init" — no separate step is needed (research.md §2).
- [ ] T018 [P] [US1] Write `scripts/fetch-recovery-password.sh`: SSHes as `${admin_username}` on `${ssh_port}`, uses sudo to `cat` the root-only password file written in T012, prints the value to stdout exactly once, then deletes that file from the instance so nothing recoverable remains on disk (FR-008, research.md §3)
- [ ] T020 [P] [US1] Write `scripts/lockdown-ssh.sh`: rewrites `/etc/ssh/sshd_config.d/00-admin.conf` to contain `Port ${ssh_port}`, `PermitRootLogin no`, and `PasswordAuthentication no`; restarts whichever of `ssh.service`/`ssh.socket` is active (FR-013)
- [ ] T021 [P] [US1] Write `scripts/print-connection-info.sh`: prints the server's `label`, `ip_address`, `admin_username`, and `ssh_port` as the FR-016 connection record, and nothing else
- [ ] T022 [US1] In `main.tf`, add a `terraform_data` that `depends_on` the `vultr_instance`, with `local-exec` provisioners invoking, strictly in this order, T017 → T018 → T020 → T021, so that a non-zero exit from any step aborts every step after it (FR-010, FR-018, research.md §2)
- [ ] T023 [P] [US1] Create `outputs.tf` exposing exactly `label`, `ip_address`, `admin_username`, and `ssh_port`, matching contracts/interface.md's Output contract table — no secret value may appear in any output
- [ ] T024 [US1] Run quickstart.md Steps 1–3 against one real, disposable Vultr instance: confirm the apply succeeds, the recovery password and key passphrase are each shown exactly once, and every Step 3 check passes (admin key+sudo access works; root login over `ssh_port` is refused; `unattended-upgrades` is enabled; the firewall group allows only `ssh_port`/`allowed_ports`)

**Checkpoint**: User Story 1 is fully functional and independently testable — a complete happy-path run produces a hardened, auto-updating server end to end.

---

## Phase 4: User Story 2 - Fail safe instead of locking the operator out (Priority: P2)

**Goal**: When the FR-009 verification fails, the automation halts before the irreversible lock-down step and clearly reports what failed and what access the server still has — root login and password authentication are never disabled on a server the admin path can't actually reach.

**Independent Test**: Deliberately break the administrative access path (e.g. point `scripts/verify-admin-access.sh` at a wrong key) and confirm `terraform apply` halts with a clear failure message, and that root login and password authentication remain exactly as cloud-init left them (quickstart.md Step 4).

### Implementation for User Story 2

- [ ] T025 [US2] Edit `scripts/verify-admin-access.sh` (from T017) to, on failure, print which specific check failed (key authentication vs. passwordless sudo, or a timeout) and state explicitly that root login and password authentication remain untouched, satisfying FR-018's "report the failure and the server's current access state"
- [ ] T027 [US2] Review the `terraform_data` provisioner block added in `main.tf` (T022): confirm no provisioner between T017 and T020 sets `on_failure = continue` or any equivalent override, so Terraform's default fail-fast behavior is preserved for the entire verify → lock-down chain (FR-010)
- [ ] T028 [US2] Run quickstart.md Step 4 against a disposable instance: temporarily point `scripts/verify-admin-access.sh` at a deliberately wrong key, run `terraform apply`, confirm it exits non-zero with T025's diagnostic message before `scripts/lockdown-ssh.sh` (T020) runs, confirm the server is still reachable exactly as cloud-init left it, then revert the deliberate change

**Checkpoint**: Both user stories work independently — a failing verification demonstrably leaves the server at least as accessible as it was before that step started.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Final checks spanning both user stories

- [ ] T029 [P] Run `tests/validate.sh` (T004) across the finished module and fix any `terraform fmt`, `terraform validate`, or `shellcheck` findings in `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, and every `scripts/*.sh` file
- [ ] T030 [P] Write `README.md` at the repository root documenting how to provision a server: copying `servers/myserver.tfvars.example` to a new `servers/<label>.tfvars`, running `terraform apply -var-file=servers/<label>.tfvars`, and a pointer to `specs/001-vultr-server-provisioning/quickstart.md` for full validation steps
- [ ] T031 Run quickstart.md Step 5 to `terraform destroy` every disposable instance created in T024 and T028, and delete their local `~/.ssh/id_ed25519_<label>*` key files, leaving no leftover billed resources or orphaned keys

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — BLOCKS both user stories
- **User Story 1 (Phase 3)**: Depends on Foundational completion
- **User Story 2 (Phase 4)**: Depends on User Story 1 completion — it edits the scripts and provisioner chain T009–T022 created, and its independent test needs a server that already reaches the point where FR-009/FR-013 run
- **Polish (Phase 5)**: Depends on both user stories being complete

### Within Each User Story

- US1: SSH key generation (T009–T010) → instance resource (T011) → cloud-init template (T012–T015) → verify/lock-down scripts (T017, T018, T020, T021, parallel) → wiring them into the provisioner chain (T022) → outputs (T023) → end-to-end validation (T024)
- US2: failure-messaging edit (T025) → chain review (T027) → forced-failure validation (T028)

### Parallel Opportunities

- Setup: T002, T003, T004 (after T001)
- Foundational: T007 (after T005)
- US1: T012 can start alongside T009–T011; T017, T018, T020, T021, T023 are all independent files and can be written in parallel once T015 has defined what they'll be wired into
- Polish: T029, T030

---

## Parallel Example: User Story 1

```bash
# Once main.tf's instance + user_data wiring (T009-T015) is in place, write every
# gate script in parallel — each is an independent file:
Task: "Write scripts/verify-admin-access.sh"
Task: "Write scripts/fetch-recovery-password.sh"
Task: "Write scripts/lockdown-ssh.sh"
Task: "Write scripts/print-connection-info.sh"
Task: "Create outputs.tf"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks both stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Run quickstart.md Steps 1–3 against a real disposable instance
5. This is a usable MVP — an operator can already replace the entire manual runbook with one `terraform apply`

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. User Story 1 → validate independently (quickstart Steps 1–3) → this is the MVP
3. User Story 2 → validate independently (quickstart Step 4) → confirms the module is safe to trust for real use
4. Polish → static validation clean, documented, disposable test resources cleaned up

---

## Notes

- [P] tasks = different files, no dependency on an incomplete task
- [Story] label maps task to US1 or US2 for traceability
- No automated test framework is used (research.md §7) — quickstart.md runs against real infrastructure serve as the acceptance tests, called out explicitly as tasks T024 and T028
- T016 (wait-for-cloud-init.sh) and T019 (verify-new-port.sh) were dropped: verify-admin-access.sh's retry loop over `ssh_port` already covers both (research.md §2)
- T006 (`terraform.tfvars.example`) was dropped: it only restated defaults already declared in `variables.tf` (T005) and was never auto-loaded by Terraform (only a literal `terraform.tfvars` or `*.auto.tfvars` would be) — redundant with no functional purpose
- Commit after each task or logical group
- Every secret-handling task (T009, T012, T018) must be re-checked against research.md §3 before being considered done: no passphrase or recovery password may ever be written to a `.tf`-managed attribute, an output, or version control

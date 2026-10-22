# Phase 0 Research: Vultr Server Provisioning Automation

## 1. Resource provisioning mechanism

**Decision**: Use the official `vultr/vultr` Terraform provider's `vultr_ssh_key` and `vultr_instance` resources for FR-001–FR-006.

**Rationale**: Terraform gives declarative, idempotent management of the two cloud resources the runbook creates by hand (an SSH key object and an instance), with state-based tracking that naturally satisfies "don't duplicate on rerun." It's a widely adopted, actively maintained provider matching every field the runbook's `vultr-cli` commands use (`region`, `plan`, `os`/`os_id`, `label`, `ssh_key_ids`).

**Alternatives considered**:
- Plain shell script wrapping `vultr-cli` directly — rejected because it would have to hand-roll the idempotency/state tracking Terraform already provides, and loses `terraform plan`'s preview/review step.
- Vultr API via a general-purpose scripting language (Python/Go SDK) — rejected for the same reason; no state management without building it, and this repo has no existing application language convention to anchor the choice.

## 2. Orchestrating the bootstrap → verify → lock-down sequence

**Decision**: Split the sequence at the point where it genuinely needs an *external* observer, and use the cheapest mechanism on each side of that split:

- **Unattended bootstrap (admin account creation, package installs, SSH on the configured port, automatic-update configuration)** is done declaratively via **cloud-init**, passed as the `vultr_instance` resource's `user_data`. Vultr runs this automatically at first boot — no SSH-as-root step, no provisioner, required to get the instance to this point. Cloud-init writes `sshd_config.d/00-admin.conf` with a single `Port ${ssh_port}` line and leaves root login and password authentication at their defaults (enabled) — disabling those is deliberately left to the next stage.
- **The verify → lock-down gate (FR-009, FR-010, FR-013, FR-018)** — the one part of the runbook that inherently requires something *outside* the box to confirm the administrative path actually works before disabling root/password login — is done via a short, ordered chain of small scripts under `scripts/`, each invoked by a `local-exec` provisioner on a `null_resource` that depends on the instance. Each script exits non-zero on failure.

**Rationale**: cloud-init is the Terraform-idiomatic way to bootstrap a cloud instance — HashiCorp's own documentation treats `remote-exec`/`local-exec` provisioners as a last resort precisely because they're less observable and less declarative than passing the target platform's native bootstrap mechanism through `user_data`. Everything in Steps 3 and 5 of the runbook (create user, install packages, write config files, enable a systemd unit) is a one-shot, unconditional action with no dependency on feedback from outside the box, so cloud-init fits it directly and removes the need for Terraform to open an SSH session at all for that part.

What cloud-init *cannot* do is the one thing Step 4 is built around: pausing to let something outside the instance prove the administrative access path actually works before disabling root/password login. Cloud-init is fire-and-forget at boot; it has no channel to receive an external "yes, I could reach you" signal, and FR-009 is deliberately a check of *network* reachability from off-box, not a self-check the instance can run on itself. That gate therefore stays as an externally-driven `local-exec` script, run from wherever `terraform apply` executes. Terraform's existing "abort the apply on the first non-zero provisioner exit" behavior is what gives FR-018's "auto-check, halt on failure, don't disable root/password login" behavior for free, with no custom state machine.

There is no separate "wait for cloud-init" step and no dual-port SSH config: the single `verify-admin-access.sh` script retries `ssh -p ${ssh_port} ${admin_username}@<ip> 'id; sudo whoami'` with a bounded timeout. Nothing on the box can satisfy that check until cloud-init has already created the admin account and moved `sshd` to `ssh_port`, so a successful connection *is* the "cloud-init finished" signal — a separate root-key/port-22 polling step would just be checking the same underlying fact a second way. (An earlier revision of this design used a dual-port `sshd` config and a distinct root-key polling step as a stand-in for the manual runbook's "leave a terminal open" fallback; that was solving a problem specific to the manual runbook's live port *migration*, which doesn't exist here since cloud-init sets the final port once, at boot — see §9 for the same realization applied to the firewall.)

**Alternatives considered**:
- **A dual-port `sshd` config with a separate root-key bootstrap/verification step** — the original design; dropped once it became clear nothing was actually migrating ports at runtime, so the extra port and extra script were solving a non-problem.
- **cloud-init for everything, including the verify/lock-down gate** — rejected: cloud-init has no mechanism to pause for, or receive, a signal from outside the instance, so it cannot implement the "only lock down after an external check passes" requirement at the core of User Story 2.
- **A single monolithic bootstrap script doing everything in one SSH session** — rejected because it collapses the FR-009 verification gate into an un-inspectable internal step, making it harder to test User Story 2 independently as the spec requires.
- **A general-purpose configuration management tool (Ansible)** — reasonable alternative to cloud-init for the bootstrap half, but adds a second toolchain/dependency for a one-shot, boot-time action cloud-init already handles natively via `user_data`; rejected to keep the toolchain minimal unless a future feature needs Ansible's broader configuration-drift capabilities (see spec Assumptions: drift correction is explicitly out of scope for this feature).
- **Packer-built golden image** — see §8 below; deferred rather than rejected outright.

## 3. Keeping generated secrets out of state, logs, and version control

**Decision**: The SSH key pair is generated locally by a `local-exec` provisioner calling `ssh-keygen` directly to a path under the operator's `~/.ssh/`, outside of any Terraform-managed file. Only the **public** key content is read into the `vultr_ssh_key` resource (which Terraform must store in state, but public keys are not secret).

The admin console-recovery password is **generated on the instance itself**, inside cloud-init's `runcmd` (e.g. a locally-sourced random value piped into `chpasswd`), and written only to a root-owned, `600`-permission file on that instance — it never appears in the `user_data` content Terraform renders, so it never touches Terraform state. A dedicated `fetch-recovery-password.sh` step, run once via `local-exec` immediately after the FR-009 admin-access verification succeeds, connects as the admin user, uses sudo to read that file, prints the value to the operator's terminal exactly once (visible in that single `terraform apply` run's log only), and then deletes the file from the instance so nothing recoverable is left on disk afterward.

**Rationale**: Matches FR-002/FR-008 exactly and mirrors the manual runbook's existing practice (operator copies the passphrase/password into Bitwarden by hand, right after it's shown once). Generating the password on-box and never routing it through `user_data` is what makes cloud-init safe to use here at all — if the password were instead generated by Terraform and *passed into* the cloud-init template (so cloud-init only had to apply it), that value would be embedded in the rendered `user_data` string, which Terraform stores in state as a normal resource attribute regardless of whether an output is marked `sensitive`. Keeping generation on-box avoids that entirely. Terraform `sensitive = true` outputs are not used for either secret because marking an output sensitive only redacts it from CLI *display* — the value is still written to the state file in plain form, which is a stronger persistence/exposure guarantee violation than the chosen approach.

**Alternatives considered**:
- Generating the recovery password in Terraform (e.g. a `random_password` resource) and feeding it into the cloud-init template — rejected per the rationale above: it would land the plaintext password inside the `user_data` attribute Terraform persists to state.
- Terraform `sensitive` output + encrypted remote state — rejected: still persists the secret in state indefinitely, and adds a remote-state backend dependency this feature doesn't otherwise need.
- Writing secrets to a local encrypted file automatically — this was one of the options presented to the user; they chose the simpler "print once, manual save" behavior instead, consistent with today's Bitwarden workflow.

## 4. Label-collision detection (FR-018)

**Decision**: Rely on (a) per-label Terraform state isolation (one state/workspace per server label — see §5) so Terraform's own "resource already in my state" idempotency prevents duplicate creation on rerun with the same label, and (b) the Vultr API's own duplicate-name rejection for a label that exists on the account but *outside* that state, which surfaces as a failed `terraform apply` with zero resources created.

**Rationale**: Both cases stop the run "before making changes" as FR-018 requires, without needing a separate pre-flight existence-check script — the underlying platform semantics already guarantee it.

**Alternatives considered**: A custom pre-apply script that calls the Vultr API to check for an existing label/key name — rejected as redundant given the behavior above, and it would need to be kept in sync with provider-side validation rules.

## 5. State isolation per server

**Decision**: One Terraform state per server label, selected via a separate working directory or `terraform workspace` per `servers/<label>.tfvars` file, rather than one shared state managing many instances as a list/map.

**Rationale**: FR-001's "never reuse a key across servers" and the spec's "first-time provisioning only, no fleet-wide drift reconciliation" framing both point to each server being an independent unit of work the operator provisions one at a time, matching the runbook's own one-server-at-a-time narrative. Per-label state also means a mistake or `terraform destroy` on one server can never touch another's resources.

**Alternatives considered**: A single shared state with a `for_each` map of servers — rejected for this feature's scope; it would be the right shape for a future fleet-management feature, but adds blast-radius risk (one bad `apply` touching many servers) that isn't needed when SC-005's only requirement is "no collisions between independently provisioned servers," which per-label state satisfies more simply.

## 6. SSH daemon restart variant (socket-activated vs. service)

**Decision**: Both the cloud-init `runcmd` (initial restart after setting `Port ${ssh_port}`) and the later `lockdown-ssh.sh` script check `systemctl is-active ssh.socket` before restarting, and restart whichever of `ssh.service`/`ssh.socket` is actually active, exactly as the runbook's own fallback note describes.

**Rationale**: Directly resolves the "Edge Cases" item about socket-activated SSH on some Debian images; no new decision needed beyond porting the runbook's own troubleshooting step into both places the restart happens.

**Alternatives considered**: None — this is a direct port of existing, already-validated operator knowledge from the source runbook.

## 7. Testing strategy for infrastructure code

**Decision**: Static validation only in the repeatable/automatable sense (`terraform validate`, `terraform fmt -check`, `shellcheck` on all scripts), plus a documented manual quickstart run against one real, disposable Vultr instance as the end-to-end acceptance test for User Stories 1 and 2.

**Rationale**: The feature's correctness is fundamentally about side effects on a billed, real cloud resource and an irreversible SSH lockdown sequence — not logic that's meaningfully unit-testable in isolation. Static validation catches syntax/typing errors cheaply and often; the quickstart run is the actual proof that SC-001–SC-003 hold, and is cheap enough (one small instance, destroyed after) to run by hand before trusting the module.

**Alternatives considered**: Terratest or Kitchen-Terraform for automated integration tests against live infrastructure — rejected as disproportionate tooling investment for a single-module, single-operator feature; could be revisited if this module grows into a larger fleet-management system.

## 8. Pre-built image (Packer) — deferred, not rejected

**Decision**: Do not introduce Packer for this feature. Provision from the stock Debian OS image, with all configuration applied at boot by cloud-init (§2) rather than baked into a custom snapshot ahead of time.

**Rationale**: Packer's value is boot-speed and consistency at fleet scale — pre-install packages once into a golden image so each instance skips `apt-get install` at launch. Three things make it a poor fit for *this* feature specifically, as scoped:
1. The things that actually vary (the per-server SSH key, SSH port, firewall allow-list, update notification email/reboot time) are exactly the things a shared golden image can't bake in — they'd still need to be applied per-instance via cloud-init or provisioners on top of the image, so Packer wouldn't remove the need for §2's mechanism, only shave some boot time off package installs.
2. It directly duplicates the maintenance burden Step 5 exists to eliminate: a golden image needs its own rebuild/repatch cadence to stay current, which is the same "someone has to remember to keep this updated" problem `unattended-upgrades` solves for the running instance. Adding Packer now would mean maintaining freshness in two places.
3. The spec's own Assumptions explicitly scope this feature to one-server-at-a-time, first-time provisioning, not fleet management (see spec.md Assumptions) — Packer's benefit only shows up once you're launching the same image repeatedly at scale.

**Alternatives considered**: Building a Packer snapshot with `unattended-upgrades`/`apt-listchanges`/`bsd-mailx` pre-installed, then having cloud-init only apply the per-instance parameters — a reasonable future optimization if provisioning volume or boot-time latency ever becomes a real constraint, but premature for the current one-server-per-run scope. Revisit if/when a fleet-scale follow-on feature is proposed.

## 9. Firewall mechanism: Vultr Firewall Group, with no special-casing of any particular port

**Decision**: Network-level firewalling is done with a Vultr Firewall Group (`vultr_firewall_group` + `vultr_firewall_rule` resources) attached to the instance — not `ufw` inside cloud-init. The group holds exactly one rule for `ssh_port` (whatever value the operator chose, including `22`) plus one rule per `allowed_ports` entry — all plain, unconditional Terraform resources. There is no separate "default port" rule, no fallback, and no toggle variable: the module has no built-in concept of port 22 being special.

**Rationale**: Two things ruled out every alternative that involved treating port 22 specially:

1. **`ufw` doesn't reliably restrict a Docker host.** Docker manipulates `iptables` directly (its own chains, rules ahead of `ufw`'s in the `FORWARD` chain) and is well known to let published container ports bypass host-level `ufw` restrictions. Since the server this automation produces is explicitly meant to become "a Docker host, a jumpbox, a remote dev box," a firewall that Docker can silently punch holes through is the wrong default. A provider-level firewall filters traffic before it ever reaches the instance's network stack, so nothing running on the box — Docker included — can bypass it.
2. **There's no live port migration to protect, so there's nothing to fall back to.** An earlier revision of this design gave port 22 a permanent, always-present rule (for bootstrap access) plus a second conditional rule for `ssh_port`, on the theory that the two might need to coexist and then be reconciled. That reasoning doesn't hold up: cloud-init sets `ssh_port` once, at first boot — nothing is ever running on port 22 unless `ssh_port` *is* 22. Needing `ssh_port` reachable is already covered by the one unconditional rule for it; no bootstrap-specific exception is needed (§2 explains why no root-key/port-22 polling step is needed either). Changing `ssh_port` on an already-running server later is an ordinary infrastructure change the operator makes by editing this module's code and re-applying — not a capability this module provisions for.

**Alternatives considered**:
- **`ufw` configured by cloud-init** (the original design) — rejected once the Docker-bypass problem was raised; also meant firewall state lived in instance-local shell commands rather than Terraform state, which was a secondary reason to prefer Vultr Firewall Groups independent of Docker.
- **An always-present port-22 rule plus a conditional `ssh_port` rule** (`count` based on whether they're equal) — rejected: it bakes an assumption into the shared module that port 22 is a distinct, special case worth coding around, when the module should be completely agnostic to which port the operator picks.
- **A dedicated variable (e.g. `remove_ssh_fallback_port`) to toggle a fallback rule's existence across a second `terraform apply`** — rejected for the same reason: it's machinery built around a "fallback" concept that doesn't actually apply to this module's bootstrap flow, and any future port change is better left as a plain code edit the operator reviews via `terraform plan`, not a feature this module has to carry.

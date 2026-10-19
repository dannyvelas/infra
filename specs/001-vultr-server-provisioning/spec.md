# Feature Specification: Vultr Server Provisioning Automation

**Feature Branch**: `[001-vultr-server-provisioning]`

**Created**: 2026-10-18

**Status**: Draft

**Input**: User description: "Translate a manual step-by-step runbook for provisioning a new Vultr instance (dedicated SSH key, instance creation, non-root admin user with passwordless sudo, hardened SSH plus firewall, automatic security updates) into infrastructure as code, so the operator never has to perform the manual steps again."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Provision a new hardened server end-to-end (Priority: P1)

An operator who needs a new server supplies a unique label for it (and optionally a region, size, and OS image) and runs the automation once. The automation creates a dedicated access credential for that server, provisions the cloud instance, creates a non-root administrative account with passwordless privilege escalation, locks SSH down to key-only access on a non-default port with root login disabled, restricts inbound network access to only that port, and turns on automatic security updates — all without the operator typing any of the individual runbook commands by hand.

**Why this priority**: This is the entire reason the automation exists — replacing the manual, multi-terminal runbook with a single repeatable operation. Without this, nothing else in the feature has value.

**Independent Test**: Can be fully tested by running the automation against a fresh label end-to-end and confirming the resulting server matches the hardened end-state the runbook describes (key-only admin access on the custom port, root/password SSH disabled, firewall default-deny with only the custom port open, automatic updates enabled).

**Acceptance Scenarios**:

1. **Given** an operator with valid cloud provider credentials configured and no existing resources for a chosen label, **When** they run the automation with that label, **Then** a new instance is created, reachable only via the non-root administrative account over the configured SSH port, with root login and password authentication disabled and automatic security updates enabled.
2. **Given** the automation has just provisioned a server, **When** the operator inspects the result, **Then** they are given the server's address, the SSH port to use, and where to find the generated credentials — without ever having had to view or type the raw commands from the original runbook.
3. **Given** an operator reruns the automation with a label that was already used for a previous server, **When** the run starts, **Then** the automation detects the collision and stops before making changes, rather than silently overwriting or duplicating resources.

---

### User Story 2 - Fail safe instead of locking the operator out (Priority: P2)

While hardening a server, the automation must behave the same way the manual runbook does: it keeps the original root access path (default SSH port, root login, password fallback where applicable) available until the new administrative access path has been proven to work, and it refuses to proceed to the irreversible lockdown steps (disabling root login, disabling password authentication, removing the fallback firewall rule) unless that proof succeeds.

**Why this priority**: The manual runbook spends an entire step on this precaution because a mistake here permanently locks the operator out of the server. Automating the risky steps without preserving this safety property would make the automation more dangerous than the manual process it replaces.

**Independent Test**: Can be tested independently by deliberately causing the new administrative access path to fail (e.g., simulating a bad key or unreachable port) and confirming the automation stops, reports the failure clearly, and leaves the original root access path intact rather than continuing to the lockdown steps.

**Acceptance Scenarios**:

1. **Given** the administrative account has just been created on a new instance, **When** the automation checks that the account can authenticate with its dedicated key and use elevated privileges without a password prompt, **Then** the automation only proceeds to firewall and SSH hardening if that check passes.
2. **Given** the SSH port has just been changed, **When** the automation checks that the administrative account can reach the server on the new port, **Then** the automation only disables root login, disables password authentication, and removes the fallback firewall rule if that check passes.
3. **Given** either verification check fails, **When** the automation halts, **Then** the server remains reachable through its original root access path and the operator is told exactly what failed and what state the server was left in.

---

### Edge Cases

- What happens when the cloud instance stays in a pending/booting state far longer than expected, or never transitions to active?
- What happens when the SSH daemon on the chosen OS image is socket-activated, so a plain service restart doesn't pick up the new port?
- What happens when the administrative account's sudo/key verification fails partway — is port 22 and root access still open, and is that clearly communicated?
- What happens when the operator reruns provisioning with a label that collides with an existing SSH key name or instance label on the provider account?
- What happens when the operator-chosen automatic-reboot time would fall during a window when the server is expected to be in active use?
- What happens when automatic-update summary email cannot actually leave the server (no outbound mail relay configured)?
- What happens when the cloud provider API credentials are missing, expired, or invalid at the start of a run?
- What happens when the operator wants a different base OS, region, or instance size than whatever default the automation ships with?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST generate a dedicated SSH key pair for each server's administrative account, and MUST NOT reuse a key pair across more than one server.
- **FR-002**: System MUST prevent generated private key material and any associated passphrase from being committed to version control or written to logs/console output in plain form.
- **FR-003**: System MUST register the new public key with the cloud provider account before instance creation, so it can be injected into the instance's root account at first boot.
- **FR-004**: System MUST let the operator specify, per run, a unique server label and optionally a region, instance size/plan, and OS image, applying documented defaults for any left unspecified.
- **FR-005**: System MUST create the cloud instance using the registered key so that initial root access requires no emailed or manually-typed root password.
- **FR-006**: System MUST wait for the newly created instance to reach a running state and obtain its network address before attempting any further configuration.
- **FR-007**: System MUST create a non-root administrative account on the instance, authorize the server's dedicated key for that account's SSH login, and configure that account for privilege escalation without a password prompt.
- **FR-008**: System MUST set a login password on the administrative account for cloud-provider console recovery purposes only, and MUST print that password (and the key passphrase from FR-001) to the operator's terminal exactly once at generation time, for the operator to copy into their own secret storage, rather than persisting either value in the automation's own state or logs in plain form.
- **FR-009**: System MUST verify that the administrative account can authenticate using its dedicated key and exercise elevated privileges without a password prompt before any subsequent step narrows the server's access paths.
- **FR-010**: System MUST NOT disable root SSH login, disable SSH password authentication, or remove the fallback firewall rule for the default SSH port unless the verification in FR-009, and the equivalent verification of the new SSH port below (FR-013), have each succeeded.
- **FR-011**: System MUST configure the instance's firewall to deny inbound connections by default and explicitly allow only the administrative SSH port (plus any additional ports the operator designates for the server's intended workload).
- **FR-012**: System MUST move SSH access to an operator-configurable, non-default port, keeping the default SSH port reachable only as a fallback until the new port is confirmed reachable using the administrative account's key.
- **FR-013**: System MUST verify that the administrative account can reach the server over the new SSH port before the default port's fallback firewall rule is removed.
- **FR-014**: System MUST disable root SSH login and SSH password authentication only after both FR-009 and FR-013 have succeeded.
- **FR-015**: System MUST configure the instance to automatically check for and apply security updates on a recurring schedule, including cleanup of unused kernels/dependencies and an automatic reboot when an update requires one, without further operator action after initial setup.
- **FR-016**: System MUST let the operator configure the notification email address and automatic-reboot time used by the automatic-update schedule, defaulting to a reboot time outside typical working hours.
- **FR-017**: System MUST produce, for every run, a record containing the server's label, network address, administrative username, and SSH port, so the operator can connect to the server afterward without consulting the automation's internal logic.
- **FR-018**: System MUST detect when a run's chosen label collides with an existing server or credential it previously created, and MUST stop before making changes rather than overwriting or duplicating resources.
- **FR-019**: System MUST, when either the FR-009 or FR-013 verification fails, halt automatically and report the failure and the server's current access state to the operator, without proceeding to the corresponding irreversible lockdown step.

### Key Entities

- **Server Instance**: A provisioned cloud server — label, region, plan/size, OS image, current network address, and lifecycle state (pending, active, etc.).
- **SSH Key Pair**: The dedicated per-server credential — public key (registered with the provider), private key and passphrase (handed off per FR-008), and the single server/administrative account it is scoped to.
- **Administrative Account**: The non-root user created on a Server Instance — username, authorized key, passwordless-sudo privilege, and console-recovery password.
- **Hardening Configuration**: The SSH and firewall posture applied to a Server Instance — custom SSH port, root-login policy, password-authentication policy, and the set of allowed inbound ports.
- **Update Policy**: The automatic-update behavior applied to a Server Instance — update schedule, notification email, and automatic-reboot time.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator can go from "I need a new server" to a fully provisioned, hardened, auto-updating instance in a single automation run, without manually executing any of the individual commands described in the original runbook.
- **SC-002**: 100% of servers provisioned through the automation end up unreachable via root SSH login or SSH password authentication once the run completes successfully.
- **SC-003**: 100% of runs in which the post-hardening access verification fails leave the server still reachable through its original root access path — zero lockouts caused by the automation itself.
- **SC-004**: An operator's hands-on time to provision a new server (excluding instance boot wait) drops to a few minutes, compared with the multi-terminal, multi-step manual process it replaces.
- **SC-005**: Provisioning a second server under a different label produces no credential, firewall, or configuration collisions with any previously provisioned server.

## Assumptions

- The operator already has an active Vultr (or equivalent cloud provider) account with API credentials available to the automation, analogous to today's `~/.vultr-cli.yaml`.
- The operator's local environment can generate SSH key pairs (equivalent to today's `ssh-keygen` availability).
- A Debian-based OS image remains an acceptable default unless the operator overrides it per run.
- The operator has access to a secure secret-storage mechanism (e.g., a password manager) to receive and retain the generated key passphrase and console-recovery password, consistent with the Bitwarden practice in the original runbook.
- Each automation run provisions exactly one server; bulk/batch provisioning of multiple servers in a single run is out of scope for this feature.
- Configuring outbound mail relaying so automatic-update summary emails actually leave the server is out of scope, consistent with the original runbook treating it as a separate concern.
- This feature covers first-time provisioning of brand-new instances only; detecting or correcting configuration drift on a previously-provisioned server is out of scope and may be addressed by a future feature.

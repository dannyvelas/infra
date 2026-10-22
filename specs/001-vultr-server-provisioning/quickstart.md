# Quickstart: Validating the Vultr Server Provisioning Automation

This is a runnable validation guide, not an implementation spec — it proves User Stories 1 and 2 end-to-end against one real, disposable Vultr instance. See [data-model.md](./data-model.md) for field definitions and [contracts/interface.md](./contracts/interface.md) for the exact input/output contract referenced below.

## Prerequisites

- Terraform >= 1.5 installed locally.
- `ssh-keygen` and `ssh` available locally (bundled with OpenSSH).
- A Vultr account with an API key configured for the `vultr/vultr` Terraform provider (equivalent to today's `~/.vultr-cli.yaml`).
- `shellcheck` installed locally, for the static-validation step.

## Step 1: Static validation (fast, no cloud cost)

```sh
terraform fmt -check
terraform validate
shellcheck scripts/*.sh
```

**Expected outcome**: all three commands exit `0`. This is the automatable regression check referenced in `research.md` §7 — run it before every real-instance test below.

## Step 2: Provision a disposable test server (proves User Story 1)

Create `servers/quickstart-test.tfvars` from `servers/myserver.tfvars.example`, setting `label = "quickstart-test"` and leaving everything else at its documented default.

```sh
terraform apply -var-file=servers/quickstart-test.tfvars
```

**Expected outcome**:
- The apply completes successfully and prints the SSH key passphrase and the admin console-recovery password to the terminal exactly once (copy them into your own secret storage now — per the output contract, they are not persisted anywhere by the automation).
- The four outputs defined in `contracts/interface.md` (`label`, `ip_address`, `admin_username`, `ssh_port`) are printed at the end of the run.

## Step 3: Confirm the hardened end-state

Using the `ip_address` and `ssh_port` from Step 2's output:

```sh
ssh -p <ssh_port> -i ~/.ssh/id_ed25519_quickstart-test admin@<ip_address> 'id; sudo whoami'   # expect: admin in sudo group; "root" with no password prompt
ssh -p <ssh_port> root@<ip_address>                                                            # expect: connection refused (root login disabled)
ssh -p <ssh_port> -i ~/.ssh/id_ed25519_quickstart-test admin@<ip_address> 'systemctl is-enabled unattended-upgrades'  # expect: enabled
```

Also confirm, from the Vultr dashboard or `vultr-cli firewall rule list <firewall-group-id>`, that the firewall group allows only `ssh_port` (and any `allowed_ports`) — nothing else.

**Expected outcome**: every command above matches its stated expectation. This is the concrete proof for SC-001 and SC-002.

## Step 4: Prove the lockout-safety behavior (proves User Story 2)

In a scratch copy of the module, temporarily point `scripts/verify-admin-access.sh` at a deliberately wrong key path (or otherwise force the FR-009 check to fail), then:

```sh
terraform apply -var-file=servers/quickstart-test.tfvars
```

**Expected outcome**: `apply` exits non-zero at the verification step; the error output names the failed check. Confirm the server is still reachable exactly as it was before this run (root over the original path, or admin over whatever state the previous successful run left it in) — this is the concrete proof for SC-003. Revert the deliberate change afterward.

## Step 5: Clean up

```sh
terraform destroy -var-file=servers/quickstart-test.tfvars
```

Also delete the local `~/.ssh/id_ed25519_quickstart-test*` key files and the corresponding entry from your secret storage — the dedicated-key-per-server rule (FR-001) means this test key must not be reused for a future quickstart run.

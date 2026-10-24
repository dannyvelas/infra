# infra

Terraform module that provisions a hardened Vultr server: a dedicated SSH key, the instance itself, a non-root admin user with passwordless sudo, a firewall, hardened SSH, and automatic security updates.

## Prerequisites

- Terraform >= 1.5
- `ssh-keygen` and `ssh` (OpenSSH)
- `VULTR_API_KEY` set in your environment

## Usage

Copy the per-server template and set a unique label:

```sh
cp servers/myserver.tfvars.example servers/<label>.tfvars
```

Edit `servers/<label>.tfvars` to set `label` (and override anything else you need — see `variables.tf` for the full list and defaults). Then:

```sh
terraform init
terraform apply -var-file=servers/<label>.tfvars
```

The apply prints the SSH key passphrase and the admin console-recovery password to your terminal exactly once — copy them into your own secret storage before closing that terminal. Connection details (`ip_address`, `admin_username`, `ssh_port`) are available afterward via `terraform output`.

## Validation

See [specs/001-vultr-server-provisioning/quickstart.md](specs/001-vultr-server-provisioning/quickstart.md) for the full end-to-end validation steps.

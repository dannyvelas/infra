# infra

Terraform module that provisions a hardened Vultr server: a dedicated SSH key, the instance itself, a non-root admin user with passwordless sudo, a firewall, hardened SSH, and automatic security updates.

Set `enable_kamal = true` in a server's `main.tf` to also provision it to run [kamal](https://kamal-deploy.org/): this installs Docker from its official apt repo, creates a passwordless, sudo-less `deploy` user for kamal's SSH access, and opens the firewall for kamal-proxy's HTTP/HTTPS traffic. Everything after that (writing `config/deploy.yml`, Bitwarden secrets, `kamal setup`/`deploy`) stays a manual, app-repo-level step.

## Prerequisites

- Terraform >= 1.5
- `ssh-keygen` and `ssh` (OpenSSH)
- `VULTR_API_KEY` set in your environment

## Layout

- `modules/server/` — the module itself. Nothing is applied from here.
- `servers/<label>/` — one Terraform root per server, holding that server's settings as committed HCL and its own state. Adding, changing, or destroying one server never touches another.
- `servers/_template/` — the starting point for a new server. Not a real server; never applied directly.

## Usage

Copy the template into a directory named for the new server:

```sh
cp -r servers/_template servers/<label>
```

Edit `servers/<label>/main.tf` and set `label` to `<label>`, matching the directory name. Adjust the other arguments as that server needs — all of them are listed explicitly so the file is a complete record of the server; see `modules/server/variables.tf` for what each one means. Then:

```sh
terraform -chdir=servers/<label> init
terraform -chdir=servers/<label> apply
```

The apply prints the SSH key passphrase and the admin console-recovery password to your terminal exactly once — copy them into your own secret storage before closing that terminal. Connection details (`ip_address`, `admin_username`, `ssh_port`) are available afterward via `terraform -chdir=servers/<label> output`.

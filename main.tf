# Provisions one hardened Vultr server per `terraform apply`: a dedicated SSH
# key, the instance itself, and (via cloud-init/user-data.yaml.tftpl plus the
# scripts/ chain below) a locked-down admin account, firewall, and automatic
# security updates.

provider "vultr" {
  # Reads the API key from the VULTR_API_KEY environment variable
  # (the equivalent of today's ~/.vultr-cli.yaml).
  rate_limit  = 500
  retry_limit = 3
}

locals {
  ssh_private_key_path = "${pathexpand("~/.ssh")}/id_ed25519_${var.label}"
}

# Generate a dedicated key pair for this label only, entirely outside
# Terraform-managed state. Never reused across servers.
resource "null_resource" "generate_ssh_key" {
  triggers = {
    label = var.label
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/generate-ssh-key.sh ${var.label}"
  }
}

# Only the public key is read back into Terraform — the private key and its
# passphrase never touch any .tf-managed attribute or state.
data "local_file" "admin_public_key" {
  filename   = "${local.ssh_private_key_path}.pub"
  depends_on = [null_resource.generate_ssh_key]
}

# Register the public key with Vultr so it can be injected into root's
# authorized_keys at first boot.
resource "vultr_ssh_key" "admin" {
  name    = "${var.label}-admin"
  ssh_key = trimspace(data.local_file.admin_public_key.content)
}

# Create the instance using the registered key, so initial root access
# requires no emailed/typed password. user_data is wired in separately
# (see cloud-init/user-data.yaml.tftpl) once that template exists.
resource "vultr_instance" "server" {
  label       = var.label
  region      = var.region
  plan        = var.plan
  os_id       = var.os_id
  ssh_key_ids = [vultr_ssh_key.admin.id]
}

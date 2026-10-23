# this reads the api key from VULTR_API_KEY
provider "vultr" {
  rate_limit  = 500
  retry_limit = 3
}

locals {
  ssh_private_key_path = "${pathexpand("~/.ssh")}/id_ed25519_${var.label}"
}

resource "null_resource" "generate_ssh_key" {
  triggers = {
    label = var.label
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/generate-ssh-key.sh ${var.label}"
  }
}

data "local_file" "admin_public_key" {
  filename   = "${local.ssh_private_key_path}.pub"
  depends_on = [null_resource.generate_ssh_key]
}

resource "vultr_ssh_key" "admin" {
  name    = "${var.label}-admin"
  ssh_key = trimspace(data.local_file.admin_public_key.content)
}

resource "vultr_firewall_group" "admin" {
  description = "${var.label}-admin"
}

resource "vultr_firewall_rule" "ssh" {
  firewall_group_id = vultr_firewall_group.admin.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = tostring(var.ssh_port)
  notes             = "administrative SSH access"
}

resource "vultr_firewall_rule" "allowed" {
  for_each = toset([for p in var.allowed_ports : tostring(p)])

  firewall_group_id = vultr_firewall_group.admin.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = each.value
  notes             = "operator-designated workload port"
}

resource "vultr_instance" "server" {
  label             = var.label
  region            = var.region
  plan              = var.plan
  os_id             = var.os_id
  ssh_key_ids       = [vultr_ssh_key.admin.id]
  firewall_group_id = vultr_firewall_group.admin.id
  user_data = templatefile("${path.module}/cloud-init/user-data.yaml.tftpl", {
    admin_username             = var.admin_username
    admin_public_key           = trimspace(data.local_file.admin_public_key.content)
    ssh_port                   = var.ssh_port
    update_notification_email  = var.update_notification_email
    update_reboot_time         = var.update_reboot_time
  })
}

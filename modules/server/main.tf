locals {
  ssh_private_key_path      = "${pathexpand("~/.ssh")}/id_ed25519_${var.label}"
  recovery_private_key_path = "${pathexpand("~/.ssh")}/id_ed25519_${var.label}-recovery"

  user_data = templatefile("${path.module}/cloud-init/user-data.yaml.tftpl", {
    admin_username            = var.admin_username
    admin_public_key          = trimspace(data.local_file.admin_public_key.content)
    recovery_public_key       = trimspace(data.local_file.recovery_public_key.content)
    ssh_port                  = var.ssh_port
    update_notification_email = var.update_notification_email
    update_reboot_time        = var.update_reboot_time
    enable_kamal              = var.enable_kamal
  })
}

resource "terraform_data" "generate_ssh_key" {
  triggers_replace = {
    label = var.label
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/generate-ssh-key.sh ${var.label}"
  }
}

data "local_file" "admin_public_key" {
  filename   = "${local.ssh_private_key_path}.pub"
  depends_on = [terraform_data.generate_ssh_key]
}

resource "terraform_data" "generate_recovery_key" {
  triggers_replace = {
    label = var.label
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/generate-recovery-key.sh ${var.label}"
  }
}

data "local_file" "recovery_public_key" {
  filename   = "${local.recovery_private_key_path}.pub"
  depends_on = [terraform_data.generate_recovery_key]
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

resource "vultr_firewall_rule" "kamal_proxy" {
  for_each = var.enable_kamal ? toset(["80", "443"]) : toset([])

  firewall_group_id = vultr_firewall_group.admin.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = each.value
  notes             = "kamal-proxy HTTP/HTTPS"
}

resource "terraform_data" "user_data" {
  triggers_replace = {
    user_data = sha256(local.user_data)
  }
}

resource "vultr_instance" "server" {
  label             = var.label
  region            = var.region
  plan              = var.plan
  os_id             = var.os_id
  ssh_key_ids       = [vultr_ssh_key.admin.id]
  firewall_group_id = vultr_firewall_group.admin.id
  user_data         = local.user_data

  # this makes it so that if we change something in cloud-init it triggers
  # a replacement of the whole instance
  lifecycle {
    replace_triggered_by = [terraform_data.user_data]
  }
}

resource "terraform_data" "verify_and_lockdown" {
  depends_on = [vultr_instance.server]

  triggers_replace = {
    instance_id = vultr_instance.server.id
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/verify-admin-access.sh ${vultr_instance.server.main_ip} ${var.ssh_port} ${var.admin_username} ${local.ssh_private_key_path}"
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/fetch-recovery-password.sh ${vultr_instance.server.main_ip} ${var.ssh_port} ${var.admin_username} ${local.ssh_private_key_path}"
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/print-and-delete-recovery-key.sh ${local.recovery_private_key_path} ${var.label}"
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/lockdown-ssh.sh ${vultr_instance.server.main_ip} ${var.ssh_port} ${var.admin_username} ${local.ssh_private_key_path}"
  }
}

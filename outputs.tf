# this file exists not because something is reading these outputs
# but because we want these values to be durable and queryable 
# without this file, this is only printed when apply is run the first
# time. otherwise, we would have to dig through a state file
output "label" {
  value = var.label
}

output "ip_address" {
  value = vultr_instance.server.main_ip
}

output "admin_username" {
  value = var.admin_username
}

output "ssh_port" {
  value = var.ssh_port
}

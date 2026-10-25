terraform {
  required_version = ">= 1.5"

  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.19"
    }
  }
}

# this reads the api key from VULTR_API_KEY
provider "vultr" {
  rate_limit  = 500
  retry_limit = 3
}

module "server" {
  source = "../../modules/server"

  label                     = "parkspot-kamal"
  region                    = "mia"
  plan                      = "vc2-1c-1gb"
  os_id                     = 2136
  admin_username            = "admin"
  ssh_port                  = 27983
  allowed_ports             = []
  update_notification_email = "admin@example.com"
  update_reboot_time        = "04:00"
  enable_kamal              = true
}

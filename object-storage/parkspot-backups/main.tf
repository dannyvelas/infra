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

data "vultr_object_storage_cluster" "this" {
  filter {
    name   = "region"
    values = ["mia"]
  }
}

data "vultr_object_storage_tier" "this" {
  filter {
    name   = "region"
    values = ["mia"]
  }
}

resource "vultr_object_storage" "backups" {
  cluster_id = data.vultr_object_storage_cluster.this.id
  tier_id    = data.vultr_object_storage_tier.this.id
  label      = "parkspot-backups"
}

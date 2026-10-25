terraform {
  required_version = ">= 1.5"

  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.19"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

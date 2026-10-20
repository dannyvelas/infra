variable "label" {
  type        = string
  description = "Unique label for this server. Used as the Vultr instance label and the SSH key name (FR-004, FR-018). Must be unique per server — never reused."

  validation {
    condition     = length(trimspace(var.label)) > 0
    error_message = "label must not be empty."
  }
}

variable "region" {
  type        = string
  description = "Vultr region code (FR-004). Defaults to Miami; override with `vultr-cli regions list` output for your preferred region."
  default     = "mia"
}

variable "plan" {
  type        = string
  description = "Vultr plan/size code (FR-004). Defaults to the smallest general-purpose instance; override with `vultr-cli plans list` output."
  default     = "vc2-1c-1gb"
}

variable "os_id" {
  type        = number
  description = "Vultr OS image ID (FR-004). Defaults to a Debian image; confirm the current ID with `vultr-cli os list | grep -i debian` before relying on this default, as provider-side IDs can change."
  default     = 2136
}

variable "admin_username" {
  type        = string
  description = "Non-root administrative username created on the instance (FR-007)."
  default     = "admin"
}

variable "ssh_port" {
  type        = number
  description = "Non-default SSH port the administrative account will use after hardening (FR-012). Must be used consistently in every ssh/scp command against this server afterward."
  default     = 27983

  validation {
    condition     = var.ssh_port >= 1 && var.ssh_port <= 65535
    error_message = "ssh_port must be a valid TCP port (1-65535)."
  }
}

variable "allowed_ports" {
  type        = list(number)
  description = "Additional inbound TCP ports to allow through the firewall beyond ssh_port, for this server's intended workload (FR-011)."
  default     = []

  validation {
    condition     = alltrue([for p in var.allowed_ports : p >= 1 && p <= 65535])
    error_message = "Every entry in allowed_ports must be a valid TCP port (1-65535)."
  }
}

variable "update_notification_email" {
  type        = string
  description = "Email address unattended-upgrades uses for its local mail summary (FR-016). This only queues local mail; it will not leave the server without a configured outbound relay (see spec Assumptions)."
  default     = "admin@example.com"
}

variable "update_reboot_time" {
  type        = string
  description = "Time of day (HH:MM, instance local time) unattended-upgrades may automatically reboot the server if an upgrade requires it (FR-016). Defaults to an off-hours time."
  default     = "04:00"
}

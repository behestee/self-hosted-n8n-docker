# ── AWS ──────────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region to deploy all resources into (e.g. us-east-1, ap-southeast-1)"
  type        = string
  default     = "us-east-1"
}

# ── EC2 ──────────────────────────────────────────────────────────────────────

variable "instance_type" {
  description = "EC2 instance type. t3.small = budget, t3.medium = recommended for teams"
  type        = string
  default     = "t3.medium"
}

variable "your_ip_cidr" {
  description = "Your public IP address in CIDR notation (e.g. 203.0.113.10/32). Only this IP can SSH into the server. Find your IP at https://checkip.amazonaws.com"
  type        = string
  # No default — must be provided in terraform.tfvars
}

variable "n8n_domain" {
  description = "Your n8n subdomain (e.g. n8n.example.com). Used as a tag on the instance for reference."
  type        = string
  default     = ""
}

# ── EC2 Scheduler ─────────────────────────────────────────────────────────────
# Add, edit, or remove entries to manage your schedules.
# All cron expressions use UTC. The timezone field lets EventBridge convert
# to a local timezone for you — useful so your schedule survives DST shifts.
# Cron format: cron(Minutes Hours Day-of-month Month Day-of-week Year)

variable "schedules" {
  description = "Map of schedule_name => {start_cron, stop_cron, timezone}. The schedule_name must match the value of the Schedule tag on your EC2 instances."
  type = map(object({
    start_cron = string
    stop_cron  = string
    timezone   = string
  }))

  default = {
    "business-hours" = {
      start_cron = "cron(0 9 ? * MON-FRI *)"   # 09:00 Mon–Fri
      stop_cron  = "cron(0 18 ? * MON-FRI *)"  # 18:00 Mon–Fri
      timezone   = "UTC"
    }
    "dev-hours" = {
      start_cron = "cron(0 8 ? * MON-FRI *)"   # 08:00 Mon–Fri
      stop_cron  = "cron(0 17 ? * MON-FRI *)"  # 17:00 Mon–Fri
      timezone   = "UTC"
    }
    "extended-hours" = {
      start_cron = "cron(0 7 ? * MON-FRI *)"   # 07:00 Mon–Fri
      stop_cron  = "cron(0 22 ? * MON-FRI *)"  # 22:00 Mon–Fri
      timezone   = "UTC"
    }
    "weekdays-only" = {
      start_cron = "cron(0 8 ? * MON *)"        # 08:00 every Monday
      stop_cron  = "cron(0 23 ? * FRI *)"       # 23:00 every Friday
      timezone   = "UTC"
    }
    "night-batch" = {
      start_cron = "cron(0 22 * * ? *)"         # 22:00 every day
      stop_cron  = "cron(0 6 * * ? *)"          # 06:00 every day
      timezone   = "UTC"
    }
    "weekend-only" = {
      start_cron = "cron(0 8 ? * SAT *)"        # 08:00 every Saturday
      stop_cron  = "cron(0 23 ? * SUN *)"       # 23:00 every Sunday
      timezone   = "UTC"
    }
  }
}

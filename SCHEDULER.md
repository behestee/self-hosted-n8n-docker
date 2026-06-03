# EC2 Scheduled Auto Start / Stop

Automatically start and stop your EC2 instance on a schedule using AWS Lambda and EventBridge Scheduler. You tag each instance with a schedule name and the system does the rest.

> **Setup is done entirely via Terraform.**
> See [terraform/README.md](terraform/README.md) for the step-by-step deployment guide.
> All schedules below are created automatically when you run `terraform apply`.

---

## How It Works

```
EventBridge Scheduler (cron timer)
          │
          │  fires at scheduled time with payload:
          │  { "action": "start", "schedule_name": "business-hours" }
          ▼
    Lambda Function  (ec2-scheduler)
          │
          │  finds all EC2 instances tagged:  Schedule = business-hours
          │  checks current state — only acts if the instance needs changing
          ▼
    EC2 Instance  ──▶  started or stopped
```

Because n8n has a systemd auto-start service (see Step 15 of [README.md](README.md)), when the EC2 instance starts, Docker, Postgres, Redis, n8n, and the worker all come up automatically — no manual action needed.

---

## Available Schedules

All times are UTC unless you set a `timezone` in `variables.tf`. Add one of these values as a `Schedule` tag on any EC2 instance to activate it.

| Tag value | Starts | Stops | Description |
|---|---|---|---|
| `business-hours` | Mon–Fri 09:00 | Mon–Fri 18:00 | Standard office hours |
| `dev-hours` | Mon–Fri 08:00 | Mon–Fri 17:00 | Developer workday |
| `extended-hours` | Mon–Fri 07:00 | Mon–Fri 22:00 | Early start, late finish |
| `weekdays-only` | Monday 08:00 | Friday 23:00 | On all week, off all weekend |
| `night-batch` | Daily 22:00 | Daily 06:00 | Overnight processing |
| `weekend-only` | Saturday 08:00 | Sunday 23:00 | Weekend jobs only |

> **To opt a server out of scheduling** — simply do not add a `Schedule` tag. Lambda only touches instances it finds by tag.

---

## Tagging an Instance

After Terraform creates your infrastructure, tag the EC2 instance to activate a schedule.

### Option A — AWS Console

1. Go to **EC2** → **Instances** in the AWS Console.
2. Tick the checkbox next to your instance.
3. Click the **Tags** tab → **Manage tags** → **Add tag**.
4. Set **Key** = `Schedule`, **Value** = any tag value from the table above.
5. Click **Save**.

### Option B — AWS CLI

Terraform prints a ready-to-run command in its output:

```bash
# The instance ID and region are filled in by Terraform output
terraform -chdir=terraform output -raw tag_this_instance | bash
```

Or run it manually (replace the values):

```bash
aws ec2 create-tags \
  --region us-east-1 \
  --resources i-0abc1234567890def \
  --tags Key=Schedule,Value=business-hours
```

### Changing the schedule

Update the tag value to a different schedule name. No Lambda or Terraform changes are needed — the new schedule takes effect at the next trigger time.

### Removing the schedule

Delete the `Schedule` tag. Lambda will find no matching instances and do nothing.

---

## Adding a Custom Schedule

If the pre-defined schedules do not fit, add your own in `terraform/variables.tf`:

```hcl
"my-schedule" = {
  start_cron = "cron(0 7 ? * MON-FRI *)"    # 07:00 Mon–Fri
  stop_cron  = "cron(0 21 ? * MON-FRI *)"   # 21:00 Mon–Fri
  timezone   = "America/New_York"             # Local timezone — handles DST automatically
}
```

Then apply:

```bash
cd terraform
terraform apply
```

Terraform creates two new EventBridge rules for your schedule. Tag any instance with `Schedule=my-schedule` to use it.

---

## Cron Expression Reference

EventBridge uses a 6-field cron (not the standard 5-field Linux cron):

```
cron( Minutes  Hours  Day-of-month  Month  Day-of-week  Year )
```

**Rules:**
- One of `Day-of-month` or `Day-of-week` must always be `?` (not both).
- Day names: `SUN MON TUE WED THU FRI SAT`
- `*` = every, `-` = range, `,` = list

**Examples:**

| Goal | Cron expression |
|---|---|
| Every day at 8 AM | `cron(0 8 * * ? *)` |
| Weekdays at 7:30 AM | `cron(30 7 ? * MON-FRI *)` |
| Every Monday at midnight | `cron(0 0 ? * MON *)` |
| Mon, Wed, Fri at 9 AM | `cron(0 9 ? * MON,WED,FRI *)` |
| First day of month at 6 AM | `cron(0 6 1 * ? *)` |

You can validate any expression in the EventBridge Console — it shows the next 10 trigger times below the input field.

---

## Timezone Reference

The `timezone` field in `variables.tf` accepts any IANA timezone string. Using a local timezone means your schedule shifts automatically for daylight saving time — you do not need to update cron expressions twice a year.

| Location | IANA timezone |
|---|---|
| US Eastern | `America/New_York` |
| US Pacific | `America/Los_Angeles` |
| US Central | `America/Chicago` |
| UK | `Europe/London` |
| India | `Asia/Kolkata` |
| Gulf (UAE) | `Asia/Dubai` |
| Japan | `Asia/Tokyo` |
| Singapore | `Asia/Singapore` |
| Australia Eastern | `Australia/Sydney` |

---

## Disabling / Removing a Schedule

| What you want | What to do |
|---|---|
| Stop scheduling one instance | Delete the `Schedule` tag from the instance |
| Pause all triggers temporarily | In EventBridge console → Schedules → disable the rules |
| Remove a schedule entirely | Delete its entry from `variables.tf` → `terraform apply` |

---

## Cost

| Service | Free tier | Typical monthly cost |
|---|---|---|
| Lambda | 1 million invocations free | ~$0.00 for a few rules/day |
| EventBridge Scheduler | 14 million invocations free | ~$0.00 |
| CloudWatch Logs | 5 GB free | ~$0.00 |

The saving comes from the EC2 instance itself. Example:

| Schedule | Hours on per month | Approx. monthly cost (t3.medium) |
|---|---|---|
| 24/7 (always on) | 730 h | ~$30 |
| `business-hours` Mon–Fri 9–6 | ~195 h | ~$8 |
| `dev-hours` Mon–Fri 8–5 | ~180 h | ~$7 |
| `weekdays-only` | ~260 h | ~$11 |

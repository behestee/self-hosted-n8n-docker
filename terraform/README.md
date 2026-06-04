# Terraform — AWS Infrastructure for n8n

This Terraform configuration provisions **all AWS infrastructure** needed to run n8n with a single command. It also sets up the automatic start/stop scheduler described in [SCHEDULER.md](../SCHEDULER.md).

After `terraform apply`, you will have a server IP, an SSH key, and a ready-to-use server. You then follow [README.md](../README.md) to install n8n on it.

---

## What Terraform Creates

| Resource | Details |
|---|---|
| **SSH key pair** | 4096-bit RSA — private key saved to `terraform/n8n-key.pem` |
| **Security group** | Port 22 open to your IP only; 80 and 443 open to everyone |
| **EC2 instance** | Amazon Linux 2023, latest AMI auto-selected, 30 GB gp3 disk |
| **Elastic IP** | Fixed public IP — stays the same even when the server is stopped |
| **IAM role (Lambda)** | Least-privilege: DescribeInstances, Start/StopInstances, CloudWatch logs |
| **IAM role (EventBridge)** | Allows EventBridge Scheduler to invoke the Lambda function |
| **Lambda function** | `ec2-scheduler` — finds instances by Schedule tag and starts/stops them |
| **EventBridge schedule group** | Groups all rules under `ec2-scheduler` |
| **EventBridge schedules** | One start + one stop rule per entry in `var.schedules` |

---

## Prerequisites

You need three things installed on your **local computer** (not the server):

### 1 — Terraform

**Mac:**
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

**Windows:** Download the installer from [developer.hashicorp.com/terraform/downloads](https://developer.hashicorp.com/terraform/downloads) and run it.

**Linux (Amazon Linux / Ubuntu):**
```bash
sudo yum install -y yum-utils   # Amazon Linux
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum install -y terraform
```

Verify: `terraform version` — should show `Terraform v1.5.x` or higher.

### 2 — AWS CLI

**Mac:**
```bash
brew install awscli
```

**Windows / Linux:** Follow the [official AWS guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).

Verify: `aws --version`

---

## Step-by-Step Deployment

### Step 1 — Clone This Repository

```bash
# Move to the home directory
cd ~

# Clone the repository
git clone https://github.com/behestee/self-hosted-n8n-docker.git n8n_terraform

# Enter the project folder
cd n8n_terraform
```

### Step 2 — Find your public IP

Terraform locks SSH access to your IP only. Open a browser and visit:

```
https://checkip.amazonaws.com
```

Copy the IP address shown (e.g. `203.0.113.42`). You will need it in the next step.

### Step 3 — Create your variables file

```bash
# Run this from the terraform/ directory
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` in any text editor and fill in your values:

```hcl
aws_region    = "us-east-1"           # Your preferred AWS region
instance_type = "t3.medium"           # t3.small for budget, t3.medium for teams
your_ip_cidr  = "203.0.113.42/32"    # Your IP from Step 1 — must end with /32
n8n_domain    = "n8n.example.com"     # Your planned n8n subdomain (used as a tag)
```

Save the file. It is listed in `.gitignore` and will not be committed.


### 4 — AWS credentials configured

Terraform uses your AWS credentials to create resources. The easiest way to set them up:

```bash
aws configure
```

It will ask for four values:

| Prompt | Where to find it |
|---|---|
| AWS Access Key ID | AWS Console → IAM → Users → your user → Security credentials → Create access key |
| AWS Secret Access Key | Shown once when you create the access key — copy it immediately |
| Default region | Use the same region you will put in `terraform.tfvars` (e.g. `us-east-1`) |
| Default output format | Type `json` and press Enter |

> Your IAM user needs admin-level permissions (or at minimum: EC2, Lambda, IAM, EventBridge, CloudWatch Logs).

Or you can keep this in .env file + direnv (recommended)

Install direnv — it auto-loads a .env file when you cd into a folder.

```bash
# Install
brew install direnv        # macOS
sudo apt install direnv    # Linux

# Add to your shell (~/.zshrc or ~/.bashrc)
eval "$(direnv hook bash)"   # or zsh
source ~/.bashrc
```

In project folder, create a .env file:

```bash
cd terraform
cp .env.example .env
# terraform/.env change the values with the actual. keep export command at each line and enclose values with inverted commas
export AWS_ACCESS_KEY_ID="AKIA_PROD..."
export AWS_SECRET_ACCESS_KEY="secret_prod..."
export AWS_DEFAULT_REGION="us-east-1"
```

Then allow it once per folder:
```bash
direnv allow    # now credentials auto-load when you enter this folder
aws sts get-caller-identity # To check loaded credentials with aws
```

### Step 5 — Initialise Terraform

This downloads the AWS, TLS, local, and archive providers. Only needed once.

```bash
cd terraform
terraform init
```

You should see:
```
Terraform has been successfully initialized!
```

### Step 6 — Preview what will be created

```bash
terraform plan
```

Terraform prints every resource it will create. Read through it and confirm it looks right. Nothing is created yet at this stage.

### Step 7 — Apply (create everything)

```bash
terraform apply
```

Terraform shows the plan again and asks:
```
Do you want to perform these actions? Enter a value:
```

Type `yes` and press Enter.

Creating all resources takes about **2–3 minutes**. When it finishes you will see the outputs:

```
Outputs:

elastic_ip          = "54.123.45.67"
ssh_command         = "ssh -i terraform/n8n-key.pem ec2-user@54.123.45.67"
instance_id         = "i-0abc1234567890def"
private_key_file    = "terraform/n8n-key.pem"
lambda_function_name = "ec2-scheduler"
schedule_names      = ["business-hours", "dev-hours", ...]
tag_this_instance   = "aws ec2 create-tags ..."
```

**Write down or copy the `elastic_ip` and `ssh_command` values.**

To see the outputs again at any time:
```bash
terraform output
```

---

## After Terraform Apply

Terraform has created your server. Now complete the n8n setup:

### 1 — Point your DNS to the Elastic IP

Go to your domain registrar and add an **A record**:

| Field | Value |
|---|---|
| Type | A |
| Name / Host | `n8n` (creates `n8n.example.com`) |
| Value | The `elastic_ip` from the Terraform output |
| TTL | 300 |

### 2 — SSH into the server

Use the `ssh_command` from the Terraform output:

```bash
ssh -i terraform/n8n-key.pem ec2-user@YOUR_ELASTIC_IP
```

> The key file (`terraform/n8n-key.pem`) was created in the `terraform/` folder of this repo by Terraform. The `chmod 400` permission was set automatically.

### 3 — Clone this repository onto the server

Everything n8n needs — Docker Compose config, Nginx config, systemd service, and setup script — lives in this repository. Clone it now from inside your SSH session:

```bash
# Install git (not pre-installed on Amazon Linux 2023)
sudo dnf install -y git

# Clone the repository into ~/n8n
git clone https://github.com/behestee/self-hosted-n8n-docker.git ~/n8n

# Enter the project directory — all following commands run from here
cd ~/n8n
```

#### Configure your environment file

```bash
# Create your .env from the template
cp .env.example .env

# Open it with the nano editor
vi .env
```

Fill in every value in the file. The key ones are:

| Variable | What to set |
|---|---|
| `POSTGRES_PASSWORD` | A strong password — 20+ random characters |
| `POSTGRES_NON_ROOT_PASSWORD` | A different strong password |
| `N8N_ENCRYPTION_KEY` | Run `openssl rand -base64 32` and paste the output |
| `N8N_HOST` | Your n8n subdomain, e.g. `n8n.example.com` |
| `WEBHOOK_URL` | `https://n8n.example.com/` — same domain with `https://` and a trailing slash |
| `SETUP_TIMEZONE` | Your server timezone, e.g. `America/New_York` or `UTC` |
| `SETUP_SSL_EMAIL` | Your email — Let's Encrypt sends renewal alerts here |
| `SETUP_INSTALL_DIR` | Leave as `/home/ec2-user/n8n` unless you cloned to a different path |

Save and exit: `ESC` → `:` → `wq` → `Enter`.

> **Encryption key is critical.** Once n8n is running and you save credentials, this key is used to encrypt them. If you ever change it, all saved credentials become unreadable. Back it up in a password manager.

### 4 — Install n8n

With the repo cloned and `.env` filled in, run the setup script to complete the entire server setup automatically — OS prep, Docker, n8n, Nginx, SSL, and the auto-start service:

```bash
bash setup.sh
```

The script reads all values from your `.env` file and handles Steps 7–15 from [README.md](../README.md) without any further manual input. It prints a progress header for each step and stops immediately if anything fails.

> If you prefer to follow each step manually instead, see **Steps 7–15** of [README.md](../README.md).

### 5 — Tag the server with a schedule (optional)

If you want the server to start and stop automatically, run the command from the `tag_this_instance` output (or go to EC2 → Instances → Tags tab in the AWS Console):

```bash
# Example — tag with the business-hours schedule
aws ec2 create-tags \
  --region us-east-1 \
  --resources i-0abc1234567890def \
  --tags Key=Schedule,Value=business-hours
```

See [SCHEDULER.md](../SCHEDULER.md) for the full list of schedules and how to manage them.

---

## Managing Schedules

### Add a new schedule

Open `terraform/variables.tf` and add a new entry to the `schedules` default block:

```hcl
"my-schedule" = {
  start_cron = "cron(0 7 ? * MON-FRI *)"   # 07:00 Mon–Fri
  stop_cron  = "cron(0 20 ? * MON-FRI *)"  # 20:00 Mon–Fri
  timezone   = "UTC"
}
```

Then apply:

```bash
terraform apply
```

Terraform will create two new EventBridge rules (`my-schedule-start` and `my-schedule-stop`). No other resources are affected.

Tag any EC2 instance with `Schedule=my-schedule` to activate it.

### Use a local timezone instead of UTC

The `timezone` field accepts any IANA timezone string. This lets you write cron times in your local clock and EventBridge handles the UTC conversion — including DST shifts.

```hcl
"us-business-hours" = {
  start_cron = "cron(0 9 ? * MON-FRI *)"    # 09:00 US Eastern
  stop_cron  = "cron(0 18 ? * MON-FRI *)"   # 18:00 US Eastern
  timezone   = "America/New_York"            # Adjusts automatically for EST/EDT
}
```

Common timezone values:

| Location | IANA timezone |
|---|---|
| US Eastern | `America/New_York` |
| US Pacific | `America/Los_Angeles` |
| UK | `Europe/London` |
| India | `Asia/Kolkata` |
| Gulf (UAE) | `Asia/Dubai` |
| Japan | `Asia/Tokyo` |
| Singapore | `Asia/Singapore` |

### Remove a schedule

Delete its entry from `variables.tf`, then run `terraform apply`. Terraform will delete the two EventBridge rules. Instances tagged with that schedule name will simply no longer be started or stopped.

---

## Useful Terraform Commands

```bash
# Preview changes without applying
terraform plan

# Apply changes
terraform apply

# View all output values
terraform output

# View a single output value (useful in scripts)
terraform output -raw elastic_ip
terraform output -raw ssh_command

# List all resources Terraform manages
terraform state list

# Refresh outputs if you applied changes outside Terraform
terraform refresh

# Completely destroy all resources — irreversible, prompts for confirmation
terraform destroy
```

---

## Important Notes

### The state file is sensitive

`terraform.tfstate` contains the private SSH key and all resource IDs in plain text. It is listed in `.gitignore`. **Do not commit it to git.**

For team use, store state remotely in an S3 bucket with versioning and a DynamoDB lock table:

```hcl
# Add to versions.tf for remote state
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "n8n/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

### Your IP may change

If your internet connection changes IP (home ISP, VPN, etc.), SSH access will be blocked. Update `your_ip_cidr` in `terraform.tfvars` and run `terraform apply` to update the security group.

### Destroying is permanent

`terraform destroy` deletes the EC2 instance and all its data. Your `.env` file and n8n database will be gone. Back up before destroying:

```bash
# Back up n8n data before destroy
ssh -i terraform/n8n-key.pem ec2-user@YOUR_IP "docker compose -f ~/n8n/docker-compose.yml down"
ssh -i terraform/n8n-key.pem ec2-user@YOUR_IP "pg_dump ..." > backup.sql
```

---

## File Reference

| File | Purpose |
|---|---|
| `versions.tf` | Terraform and provider version requirements |
| `variables.tf` | All input variables with defaults and descriptions |
| `data.tf` | Data sources: latest AL2023 AMI, default VPC and subnets |
| `ec2.tf` | SSH key pair, security group, EC2 instance, Elastic IP |
| `iam.tf` | IAM roles for Lambda execution and EventBridge invocation |
| `scheduler.tf` | Lambda function packaging, deployment, and EventBridge schedules |
| `outputs.tf` | All output values displayed after `terraform apply` |
| `lambda_function.py` | Python source for the EC2 scheduler Lambda |
| `terraform.tfvars.example` | Template — copy to `terraform.tfvars` and fill in |
| `.gitignore` | Excludes state files, key file, and zip from git |

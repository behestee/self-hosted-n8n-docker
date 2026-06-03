# Self-Hosted n8n on AWS EC2 — Complete Setup Guide

This guide walks you through every step needed to run n8n on your own server — from creating the EC2 instance all the way to a secure, SSL-protected domain. No prior server experience is assumed.

---

## Table of Contents

1. [What You Will Need](#1-what-you-will-need)
2. [Launch an EC2 Instance](#2-launch-an-ec2-instance)
3. [Assign an Elastic IP](#3-assign-an-elastic-ip)
4. [Open the Right Ports in AWS](#4-open-the-right-ports-in-aws)
5. [Point Your Domain to the Server](#5-point-your-domain-to-the-server)
6. [Connect to the Server via SSH](#6-connect-to-the-server-via-ssh)
7. [Prepare the Operating System](#7-prepare-the-operating-system)
8. [Install Docker and Docker Compose](#8-install-docker-and-docker-compose)
9. [Clone This Repository](#9-clone-this-repository)
10. [Configure the Environment File](#10-configure-the-environment-file)
11. [Start n8n with Docker Compose](#11-start-n8n-with-docker-compose)
12. [Install and Configure Nginx](#12-install-and-configure-nginx)
13. [Install a Free SSL Certificate](#13-install-a-free-ssl-certificate)
14. [Verify Everything Works](#14-verify-everything-works)
15. [Auto-Start on Server Reboot](#15-auto-start-on-server-reboot)
16. [Useful Commands](#16-useful-commands)

---

## 1. What You Will Need

- An **AWS account** (free tier is fine to start)
- A **domain name** you own (e.g. `example.com`) — any registrar works
- A computer with a terminal:
  - Mac/Linux — Terminal app is built in
  - Windows — use [Windows Terminal](https://aka.ms/terminal) or [PuTTY](https://www.putty.org/)
- The `.pem` key file you will download when creating the EC2 instance

---

## 2. Launch an EC2 Instance

1. Log in to the [AWS Console](https://console.aws.amazon.com/) and go to **EC2**.
2. Click **Launch Instance**.
3. Fill in the fields:

   | Field | Value |
   |---|---|
   | Name | `n8n-server` (or any name you like) |
   | AMI | **Amazon Linux 2023 AMI** |
   | Architecture | 64-bit (x86) |
   | Instance type | `t3.medium` (recommended) or `t3.small` (budget) |
   | Key pair | Click **Create new key pair**, name it `n8n-key`, download the `.pem` file and save it somewhere safe — you cannot download it again |
   | Storage | At least **20 GB** (increase to 30 GB if you plan heavy use) |

4. Under **Network settings**, leave the default VPC selected and tick **Allow SSH traffic from My IP** for now (you will refine this in Step 4).
5. Click **Launch Instance**. Wait about 60 seconds for the status to show **Running**.

> **Instance type guide:** `t3.small` (2 vCPU, 2 GB RAM) handles light personal use. `t3.medium` (2 vCPU, 4 GB RAM) is comfortable for team use with multiple workflows running.

---

## 3. Assign an Elastic IP

An Elastic IP is a fixed public IP address. Without it, your server's IP changes every time it restarts, breaking your domain DNS.

1. In the EC2 sidebar, click **Elastic IPs**.
2. Click **Allocate Elastic IP address** → **Allocate**.
3. Select the new IP from the list.
4. Click **Actions** → **Associate Elastic IP address**.
5. Choose your `n8n-server` instance from the dropdown and click **Associate**.

Write down this IP address — you will need it in Step 5.

---

## 4. Open the Right Ports in AWS

n8n needs to be reachable from the internet on ports 80 (HTTP) and 443 (HTTPS). SSH (port 22) should only be open to your own IP.

1. In EC2, click **Security Groups** in the sidebar.
2. Find the security group attached to your instance (usually named `launch-wizard-1` or similar).
3. Click the group, then click the **Inbound rules** tab → **Edit inbound rules**.
4. Add or verify these rules:

   | Type | Port | Source | Purpose |
   |---|---|---|---|
   | SSH | 22 | My IP | Secure admin access |
   | HTTP | 80 | Anywhere (0.0.0.0/0) | Let's Encrypt verification + redirect |
   | HTTPS | 443 | Anywhere (0.0.0.0/0) | n8n web interface |

5. Click **Save rules**.

> Do **not** open port 5678 to the internet — n8n runs internally and Nginx sits in front of it.

---

## 5. Point Your Domain to the Server

You need to create a DNS record that maps your n8n subdomain (e.g. `n8n.example.com`) to your Elastic IP.

1. Log in to your domain registrar (GoDaddy, Namecheap, Cloudflare, Route 53, etc.).
2. Find the **DNS Management** section for your domain.
3. Add an **A record**:

   | Field | Value |
   |---|---|
   | Type | A |
   | Name / Host | `n8n` (this creates `n8n.example.com`) |
   | Value / Points to | Your Elastic IP address from Step 3 |
   | TTL | 300 (or lowest available) |

4. Save the record.

DNS changes can take anywhere from a few minutes to 48 hours to fully propagate, but usually work within 5–15 minutes. You can check with:

```bash
nslookup n8n.example.com
```

It should return your Elastic IP.

---

## 6. Connect to the Server via SSH

### On Mac or Linux

Open your terminal and run:

```bash
# Move to the folder where your key file was downloaded
cd ~/Downloads

# Set correct permissions on the key (required — SSH will refuse to work otherwise)
chmod 400 n8n-key.pem

# Connect — replace YOUR_ELASTIC_IP with your actual IP
ssh -i n8n-key.pem ec2-user@YOUR_ELASTIC_IP
```

### On Windows

1. Open **Windows Terminal** or **PowerShell**.
2. Run the same commands as above. PowerShell supports `chmod` via WSL or you can use PuTTY with the key converted to `.ppk` format using **PuTTYgen**.

If it asks *"Are you sure you want to continue connecting?"* — type `yes` and press Enter.

You are now inside your server. The prompt will look like:

```
[ec2-user@ip-10-0-1-XX ~]$
```

---

## 7. Prepare the Operating System

Run each block of commands inside your server terminal.

### Update all system packages

```bash
sudo dnf update -y
```

### Install essential tools

```bash
sudo dnf install -y git curl wget unzip htop
```

### Set the correct timezone (optional but recommended)

```bash
# List available timezones
timedatectl list-timezones | grep America

# Set your timezone — replace with yours
sudo timedatectl set-timezone America/New_York
```

---

## 8. Install Docker and Docker Compose

### Install Docker

```bash
sudo dnf install -y docker
sudo systemctl start docker
sudo systemctl enable docker

# Allow your user to run Docker without sudo
sudo usermod -aG docker ec2-user

# Apply the group change — log out and back in, OR run:
newgrp docker
```

Verify Docker is working:

```bash
docker run hello-world
```

You should see a message that starts with *"Hello from Docker!"*.

### Install Docker Compose (V2 plugin)

```bash
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Verify
docker compose version
```

You should see output like `Docker Compose version v2.x.x`.

---

## 9. Clone This Repository

```bash
# Move to the home directory
cd ~

# Clone the repository
git clone https://github.com/behestee/self-hosted-n8n-docker.git n8n

# Enter the project folder
cd n8n
```

---

## 10. Configure the Environment File

The `.env` file contains passwords and settings. **Never commit this file to Git** — it is already listed in `.gitignore`.

```bash
# Copy the example file to create your real .env
cp .env.example .env

# Open it with the nano editor
nano .env
```

You will see something like this:

```
POSTGRES_USER=postgres
POSTGRES_PASSWORD=changePassword
POSTGRES_DB=n8n

POSTGRES_NON_ROOT_USER=pgn8nuser
POSTGRES_NON_ROOT_PASSWORD=changePassword

N8N_ENCRYPTION_KEY=WSVjL2Kxlfpavh7F+HRiLy7MDwrYXUMZIpUyB+4c6bQ=

N8N_HOST=n8n.techzenicsolutions.com
WEBHOOK_URL=https://n8n.techzenicsolutions.com/
...
```

### What to change

| Variable | What to set |
|---|---|
| `POSTGRES_PASSWORD` | A strong password (e.g. 20+ random characters) |
| `POSTGRES_NON_ROOT_PASSWORD` | A different strong password |
| `N8N_ENCRYPTION_KEY` | **Generate a new one** — see command below |
| `N8N_HOST` | Your n8n subdomain, e.g. `n8n.example.com` |
| `WEBHOOK_URL` | `https://n8n.example.com/` (with trailing slash) |

### Generate a secure encryption key

```bash
openssl rand -base64 32
```

Copy the output and paste it as the value of `N8N_ENCRYPTION_KEY`.

> **Critical:** The encryption key is used to encrypt your workflow credentials. If you lose it or change it later, all saved credentials will be unreadable. Back it up in a password manager.

### Save and exit nano

Press `Ctrl + X`, then `Y`, then `Enter`.

---

## 11. Start n8n with Docker Compose

```bash
# Make sure you are in the project folder
cd ~/n8n

# Start all services in the background
docker compose up -d

# Watch the startup logs to confirm everything is healthy
docker compose logs -f
```

Wait until you see log lines like:
```
n8n-n8n-1  | n8n ready on 0.0.0.0, port 5678
```

Press `Ctrl + C` to stop watching logs (this does not stop n8n).

Check that all containers are running:

```bash
docker compose ps
```

All services (`postgres`, `redis`, `n8n`, `n8n-worker`) should show status **Up**.

---

## 12. Install and Configure Nginx

Nginx acts as a reverse proxy — it receives traffic from the internet on port 443 and forwards it to n8n running internally on port 5678. It also handles SSL.

### Install Nginx

```bash
sudo dnf install -y nginx
sudo systemctl start nginx
sudo systemctl enable nginx
```

### Add rate-limiting zones to the main nginx config

Open the main Nginx config:

```bash
sudo nano /etc/nginx/nginx.conf
```

Find the `http {` block (it should be near the top). Add these two lines **inside** the `http {` block, before any `server` blocks:

```nginx
limit_req_zone  $binary_remote_addr zone=n8n_limit:10m rate=10r/s;
limit_conn_zone $binary_remote_addr zone=conn_limit:10m;
```

Save and exit (`Ctrl + X`, `Y`, `Enter`).

### Copy the n8n Nginx config

This repository includes a ready-made Nginx config file in the `nginx/` folder.

```bash
sudo cp ~/n8n/nginx/n8n.conf /etc/nginx/conf.d/n8n.conf
```

### Edit the config with your domain

```bash
sudo nano /etc/nginx/conf.d/n8n.conf
```

Find every occurrence of `YOUR_DOMAIN` in the file and replace it with your actual subdomain (e.g. `n8n.example.com`).

There are **four places** to change:
1. `server_name YOUR_DOMAIN;` in the HTTP block (line ~7)
2. `server_name YOUR_DOMAIN;` in the HTTPS block (line ~22)
3. `ssl_certificate .../YOUR_DOMAIN/fullchain.pem;`
4. `ssl_certificate_key .../YOUR_DOMAIN/privkey.pem;`
5. `ssl_trusted_certificate .../YOUR_DOMAIN/chain.pem;`
6. The `connect-src` value inside the Content-Security-Policy header

Or use this command to replace all at once (substitute `n8n.example.com` with your domain):

```bash
sudo sed -i 's/YOUR_DOMAIN/n8n.example.com/g' /etc/nginx/conf.d/n8n.conf
```

### Test the config

```bash
sudo nginx -t
```

You should see:
```
nginx: configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

> **Before reloading:** The SSL certificate paths in the config do not exist yet — Nginx will fail to start with the full HTTPS config. Complete Step 13 first, then reload Nginx.

---

## 13. Install a Free SSL Certificate

[Let's Encrypt](https://letsencrypt.org/) provides free, auto-renewing SSL certificates. Certbot is the tool that obtains and installs them.

### Install Certbot

```bash
sudo dnf install -y python3-certbot-nginx
```

### Temporarily allow HTTP-only access

Since the SSL certificate files don't exist yet, the full config will fail. Temporarily comment out the HTTPS server block so Nginx can start on port 80 only:

```bash
sudo nano /etc/nginx/conf.d/n8n.conf
```

Add a `#` at the start of every line in the `server { listen 443 ...` block, **or** simplest approach — replace the whole file content with just the HTTP block temporarily and then run Certbot:

Actually, the easier approach is to use the standalone mode:

```bash
# Stop Nginx temporarily
sudo systemctl stop nginx

# Obtain the certificate (replace n8n.example.com with your domain)
sudo certbot certonly --standalone -d n8n.example.com \
  --non-interactive --agree-tos --email your@email.com

# Start Nginx again
sudo systemctl start nginx
```

> Replace `n8n.example.com` with your domain and `your@email.com` with your real email — Let's Encrypt sends renewal reminders to this address.

Certbot will place the certificate files at:
```
/etc/letsencrypt/live/n8n.example.com/fullchain.pem
/etc/letsencrypt/live/n8n.example.com/privkey.pem
/etc/letsencrypt/live/n8n.example.com/chain.pem
```

These paths match what is already in the Nginx config (after you replaced `YOUR_DOMAIN`).

### Reload Nginx with full HTTPS config

```bash
sudo nginx -t && sudo systemctl reload nginx
```

### Enable automatic renewal

Certbot installs a systemd timer that renews certificates automatically. Verify it is active:

```bash
sudo systemctl status certbot-renew.timer
```

You can also manually test renewal with:

```bash
sudo certbot renew --dry-run
```

---

## 14. Verify Everything Works

1. Open a browser and visit `https://n8n.example.com` (use your actual domain).
2. You should see the n8n login or setup screen.
3. Click the padlock icon in the browser address bar — the certificate should show as valid and issued by *Let's Encrypt*.

If something is not working:

```bash
# Check Nginx status and recent errors
sudo systemctl status nginx
sudo tail -50 /var/log/nginx/n8n_error.log

# Check n8n container logs
docker compose -f ~/n8n/docker-compose.yml logs n8n

# Check if n8n is listening on port 5678
curl -I http://127.0.0.1:5678
```

---

## 15. Auto-Start on Server Reboot

By default, if your EC2 instance restarts (e.g. after an AWS maintenance event or a manual reboot), the Docker containers will **not** start automatically. This step creates a systemd service — a background task managed by the operating system — that starts n8n and all its dependencies every time the server boots.

This repository already includes the service file at `systemd/n8n.service`.

### Step 1 — Check the project path

The service file assumes you cloned this repository to `/home/ec2-user/n8n`. Verify that is correct:

```bash
ls ~/n8n/docker-compose.yml
```

If the file exists, you are good. If you cloned the repo to a different path, open the service file in nano and update the `WorkingDirectory` line before continuing:

```bash
nano ~/n8n/systemd/n8n.service
# Change the WorkingDirectory line to match where you cloned the repo
# Save with Ctrl+X, Y, Enter
```

### Step 2 — Copy the service file to systemd

```bash
sudo cp ~/n8n/systemd/n8n.service /etc/systemd/system/n8n.service
```

### Step 3 — Reload systemd so it sees the new file

Every time you add or edit a service file, systemd needs to be told to re-read its configuration:

```bash
sudo systemctl daemon-reload
```

### Step 4 — Enable the service

Enabling a service means systemd will start it automatically on every boot:

```bash
sudo systemctl enable n8n.service
```

You should see output like:
```
Created symlink /etc/systemd/system/multi-user.target.wants/n8n.service → /etc/systemd/system/n8n.service.
```

### Step 5 — Start the service now (without rebooting)

```bash
sudo systemctl start n8n.service
```

### Step 6 — Confirm it is running

```bash
sudo systemctl status n8n.service
```

Look for `Active: active (exited)` — this is correct and expected for a `Type=oneshot` service with `RemainAfterExit=yes`. It means the startup command ran successfully and the containers are up.

Also double-check the containers directly:

```bash
docker compose -f ~/n8n/docker-compose.yml ps
```

All four services (`postgres`, `redis`, `n8n`, `n8n-worker`) should show status **Up**.

### Step 7 — Test with a real reboot

This is the most important step. Reboot the server and confirm everything comes back on its own:

```bash
sudo reboot
```

Wait about 60–90 seconds, then SSH back in and check:

```bash
sudo systemctl status n8n.service
docker compose -f ~/n8n/docker-compose.yml ps
```

Both should show the services running without any manual intervention.

### Useful service management commands

```bash
# Check the status of the n8n service
sudo systemctl status n8n.service

# Stop n8n (does NOT disable auto-start)
sudo systemctl stop n8n.service

# Start n8n
sudo systemctl start n8n.service

# Restart n8n (stop then start)
sudo systemctl restart n8n.service

# Disable auto-start on boot (service still runs now, just won't start on reboot)
sudo systemctl disable n8n.service

# Re-enable auto-start
sudo systemctl enable n8n.service

# View the last 50 lines of startup logs
sudo journalctl -u n8n.service -n 50

# Follow live logs from the service
sudo journalctl -u n8n.service -f
```

---

## 16. Useful Commands

### n8n / Docker

```bash
# View running containers
docker compose ps

# View live logs from all services
docker compose logs -f

# View logs from n8n only
docker compose logs -f n8n

# Stop all services
docker compose down

# Start all services
docker compose up -d

# Restart a single service (e.g. after changing .env)
docker compose restart n8n

# Pull latest n8n image and recreate containers
docker compose pull && docker compose up -d

# Open a shell inside the n8n container
docker compose exec n8n sh
```

### Nginx

```bash
# Test configuration for syntax errors
sudo nginx -t

# Reload configuration without downtime
sudo systemctl reload nginx

# Full restart
sudo systemctl restart nginx

# View live access log
sudo tail -f /var/log/nginx/n8n_access.log

# View live error log
sudo tail -f /var/log/nginx/n8n_error.log
```

### SSL / Certbot

```bash
# View certificate expiry and details
sudo certbot certificates

# Force-renew certificate immediately
sudo certbot renew --force-renewal

# Dry-run renewal (tests without actually renewing)
sudo certbot renew --dry-run
```

### System

```bash
# Check disk usage
df -h

# Check memory usage
free -h

# Check CPU and process usage
htop

# Reboot the server
sudo reboot
```

---

## Security Checklist

- [x] SSH only open to your IP, not the whole internet
- [x] Port 5678 (n8n) is NOT exposed to the internet — Nginx handles all traffic
- [x] HTTPS enforced with TLS 1.2/1.3 only
- [x] Security headers set (HSTS, CSP, X-Frame-Options, etc.)
- [x] Rate limiting enabled to block brute-force attempts
- [x] Server version hidden from HTTP headers
- [x] SSL certificate auto-renews via systemd timer
- [x] n8n auto-starts on server reboot via systemd service
- [ ] Change default n8n admin password after first login
- [ ] Keep Docker images updated regularly (`docker compose pull`)
- [ ] Review AWS security group rules periodically

---

## Folder Structure

```
.
├── docker-compose.yml     # Defines all services (n8n, postgres, redis, worker)
├── .env.example           # Template for your .env file — copy and fill in
├── .env                   # Your actual secrets — never commit this file
├── init-data.sh           # Creates the non-root Postgres user on first run
├── nginx/
│   └── n8n.conf           # Nginx reverse proxy config with security headers
├── systemd/
│   └── n8n.service        # systemd unit file — auto-starts n8n on server reboot
└── README.md              # This guide
```

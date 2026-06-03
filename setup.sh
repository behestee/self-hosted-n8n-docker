#!/usr/bin/env bash
# =============================================================================
# n8n Server Setup — Steps 7 to 15
#
# Prerequisites (two manual commands before running this script):
#   sudo dnf install -y git
#   git clone https://github.com/YOUR_USER/YOUR_REPO.git ~/n8n && cd ~/n8n
#
# Then fill in your settings and run:
#   cp .env.example .env
#   nano .env
#   bash setup.sh
#
# Safe to re-run — each step checks if work is already done before acting.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colour helpers ────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m';  BOLD='\033[1m';      NC='\033[0m'

step() { echo -e "\n${CYAN}${BOLD}━━━  $*  ━━━${NC}"; }
ok()   { echo -e "${GREEN}✔  $*${NC}"; }
warn() { echo -e "${YELLOW}⚠   $*${NC}"; }
die()  { echo -e "${RED}✘  $*${NC}" >&2; exit 1; }

# ── Load .env ─────────────────────────────────────────────────────────────────
ENV_FILE="$SCRIPT_DIR/.env"
[[ -f "$ENV_FILE" ]] || die ".env not found. Run: cp .env.example .env  then fill in your values."

# Export every variable so child processes (docker compose, sed, etc.) receive them
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

# ── Validate required variables ───────────────────────────────────────────────
need() {
    local name="$1"
    local val="${!name:-}"
    [[ -n "$val" ]] || die "$name is not set in .env"
}

# Warn when a value still looks like the shipped placeholder
placeholder_check() {
    local name="$1"
    local val="${!name:-}"
    if [[ "$val" == "changePassword" || "$val" == "WSVjL2Kxlfpavh7F+HRiLy7MDwrYXUMZIpUyB+4c6bQ=" \
       || "$val" == *"example"* || "$val" == "your@email.com" ]]; then
        warn "$name still contains a placeholder value — did you forget to edit .env?"
    fi
}

need POSTGRES_PASSWORD;          placeholder_check POSTGRES_PASSWORD
need POSTGRES_NON_ROOT_PASSWORD; placeholder_check POSTGRES_NON_ROOT_PASSWORD
need ENCRYPTION_KEY;             placeholder_check ENCRYPTION_KEY
need N8N_HOST;                   placeholder_check N8N_HOST
need WEBHOOK_URL
need SETUP_SSL_EMAIL;            placeholder_check SETUP_SSL_EMAIL

DOMAIN="$N8N_HOST"
TIMEZONE="${SETUP_TIMEZONE:-UTC}"
SSL_EMAIL="$SETUP_SSL_EMAIL"
INSTALL_DIR="${SETUP_INSTALL_DIR:-/home/ec2-user/n8n}"

echo -e "\n${BOLD}n8n Setup Script${NC}"
echo   "  Domain    : $DOMAIN"
echo   "  SSL email : $SSL_EMAIL"
echo   "  Timezone  : $TIMEZONE"
echo   "  Install dir: $INSTALL_DIR"

[[ "$INSTALL_DIR" == "$SCRIPT_DIR" ]] \
    || warn "SETUP_INSTALL_DIR ($INSTALL_DIR) differs from the script location ($SCRIPT_DIR).\n   The systemd service WorkingDirectory will be set to $INSTALL_DIR."

# =============================================================================
# STEP 1 — Prepare the Operating System
# =============================================================================
step "Step 1 — Prepare the Operating System"

sudo dnf update -y
ok "System packages updated"

sudo dnf install -y wget unzip htop
ok "Essential tools installed"

sudo timedatectl set-timezone "$TIMEZONE"
ok "Timezone set to $TIMEZONE  ($(date))"

# =============================================================================
# STEP 2 — Install Docker and Docker Compose
# =============================================================================
step "Step 2 — Install Docker and Docker Compose"

if ! command -v docker &>/dev/null; then
    sudo dnf install -y docker
    sudo systemctl start docker
    sudo systemctl enable docker
    ok "Docker installed and started"
else
    ok "Docker already installed — skipping install"
    sudo systemctl enable docker --now
fi

# Add ec2-user to the docker group so future sessions work without sudo
if ! id -nG ec2-user | grep -qw docker; then
    sudo usermod -aG docker ec2-user
    ok "ec2-user added to docker group (takes effect on next login)"
else
    ok "ec2-user already in docker group"
fi

# Install Docker Compose V2 plugin
COMPOSE_PLUGIN="/usr/local/lib/docker/cli-plugins/docker-compose"
if ! sudo docker compose version &>/dev/null; then
    sudo mkdir -p "$(dirname "$COMPOSE_PLUGIN")"
    sudo curl -fsSL \
        "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
        -o "$COMPOSE_PLUGIN"
    sudo chmod +x "$COMPOSE_PLUGIN"
    ok "Docker Compose V2 installed"
else
    ok "Docker Compose already installed — skipping"
fi

ok "$(sudo docker compose version)"

# =============================================================================
# STEP 3 — Repository (already cloned — this script lives inside it)
# =============================================================================
step "Step 3 — Repository check"

[[ -f "$SCRIPT_DIR/docker-compose.yml" ]] \
    || die "docker-compose.yml not found in $SCRIPT_DIR.\nClone the repo first:  git clone <url> ~/n8n && cd ~/n8n"
ok "Repository confirmed at $SCRIPT_DIR"

# =============================================================================
# STEP 4 — Environment file
# =============================================================================
step "Step 4 — Environment file"
ok ".env loaded and key variables validated"

# =============================================================================
# STEP 5 — Start n8n with Docker Compose
# =============================================================================
step "Step 5 — Start n8n with Docker Compose"

cd "$SCRIPT_DIR"
sudo docker compose up -d
ok "Docker Compose services started"

# Wait for postgres (it has a healthcheck in docker-compose.yml)
echo "Waiting for postgres to become healthy..."
WAIT=0
until sudo docker compose ps postgres 2>/dev/null | grep -q "(healthy)"; do
    sleep 5
    WAIT=$((WAIT + 5))
    if [[ $WAIT -ge 120 ]]; then
        warn "Postgres did not report healthy within 2 minutes. Continuing anyway."
        break
    fi
    echo -n "."
done
echo ""
ok "Services are up"

sudo docker compose ps

# =============================================================================
# STEP 6 — Install and Configure Nginx
# =============================================================================
step "Step 6 — Install and Configure Nginx"

# Install nginx but do NOT start it here.
# The site config references SSL certs that don't exist until Step 13.
# Starting nginx now would cause it to fail. It starts cleanly after certbot runs.
if ! command -v nginx &>/dev/null; then
    sudo dnf install -y nginx
    ok "Nginx installed"
else
    ok "Nginx already installed — skipping"
fi

# Ensure nginx is enabled (auto-start on boot) but don't start it yet
sudo systemctl enable nginx

# Add rate-limit memory zones to the main http{} block if not already present
NGINX_MAIN="/etc/nginx/nginx.conf"
if ! grep -q "n8n_limit" "$NGINX_MAIN"; then
    sudo sed -i \
        's|http {|http {\n    limit_req_zone  $binary_remote_addr zone=n8n_limit:10m rate=10r/s;\n    limit_conn_zone $binary_remote_addr zone=conn_limit:10m;|' \
        "$NGINX_MAIN"
    ok "Rate-limit zones added to $NGINX_MAIN"
else
    ok "Rate-limit zones already present — skipping"
fi

# Copy the site config and substitute the real domain for the placeholder
NGINX_SITE="/etc/nginx/conf.d/n8n.conf"
sudo cp "$SCRIPT_DIR/nginx/n8n.conf" "$NGINX_SITE"
sudo sed -i "s/YOUR_DOMAIN/${DOMAIN}/g" "$NGINX_SITE"
ok "Site config installed at $NGINX_SITE  (domain: $DOMAIN)"

# =============================================================================
# STEP 7 — Install SSL Certificate with Let's Encrypt
# =============================================================================
step "Step 7 — Install SSL Certificate (Let's Encrypt)"

if ! command -v certbot &>/dev/null; then
    sudo dnf install -y python3-certbot-nginx
    ok "Certbot installed"
else
    ok "Certbot already installed — skipping"
fi

CERT_PATH="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"

if [[ ! -f "$CERT_PATH" ]]; then
    # Certbot standalone mode binds directly to port 80.
    # Nginx must not be running at this point (it isn't — we skipped starting it above).
    # If this is a re-run and nginx is already running, stop it first.
    if sudo systemctl is-active --quiet nginx; then
        sudo systemctl stop nginx
        warn "Nginx was running — stopped it temporarily for Certbot"
    fi

    sudo certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email  "$SSL_EMAIL" \
        -d       "$DOMAIN"

    ok "SSL certificate obtained for $DOMAIN"
else
    ok "SSL certificate already exists — skipping Certbot"
fi

# Enable auto-renewal (Amazon Linux 2023 uses a systemd timer)
sudo systemctl enable --now certbot-renew.timer
ok "Auto-renewal timer enabled"

# Now that the certs exist the full nginx config (including SSL) will load cleanly
if sudo nginx -t; then
    sudo systemctl start nginx
    ok "Nginx started with SSL configuration"
else
    die "Nginx config test failed. Fix the error above then run:\n  sudo nginx -t && sudo systemctl start nginx"
fi

# =============================================================================
# STEP 8 — Verify
# =============================================================================
step "Step 8 — Verify"

# ── Docker containers ──────────────────────────────────────────────────────
echo ""
sudo docker compose ps
echo ""

if sudo docker compose ps | grep -qiE "Exit|Error"; then
    warn "One or more containers exited. Check logs:  sudo docker compose logs"
else
    ok "All containers are running"
fi

# ── Nginx ──────────────────────────────────────────────────────────────────
if sudo systemctl is-active --quiet nginx; then
    ok "Nginx is running"
else
    warn "Nginx is not running. Check:  sudo systemctl status nginx"
fi

# ── SSL certificate expiry ─────────────────────────────────────────────────
if [[ -f "$CERT_PATH" ]]; then
    EXPIRY=$(sudo openssl x509 -enddate -noout -in "$CERT_PATH" | cut -d= -f2)
    ok "SSL certificate valid until: $EXPIRY"
else
    warn "SSL certificate not found at $CERT_PATH"
fi

# ── HTTPS reachability (best-effort — DNS may not have propagated yet) ─────
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://${DOMAIN}" 2>/dev/null || echo "000")
case "$HTTP_CODE" in
    200|301|302) ok "HTTPS check passed — https://$DOMAIN returned HTTP $HTTP_CODE" ;;
    000)         warn "Could not reach https://$DOMAIN — DNS may not have propagated yet. Try again in a few minutes." ;;
    *)           warn "https://$DOMAIN returned HTTP $HTTP_CODE — check nginx and n8n logs." ;;
esac

# =============================================================================
# STEP 9 — Auto-Start on Server Reboot (systemd)
# =============================================================================
step "Step 9 — Configure Auto-Start on Reboot"

SERVICE_SRC="$SCRIPT_DIR/systemd/n8n.service"
SERVICE_DEST="/etc/systemd/system/n8n.service"

[[ -f "$SERVICE_SRC" ]] || die "systemd service file not found at $SERVICE_SRC"

sudo cp "$SERVICE_SRC" "$SERVICE_DEST"

# Update WorkingDirectory to the actual install path from .env
sudo sed -i "s|WorkingDirectory=.*|WorkingDirectory=${INSTALL_DIR}|" "$SERVICE_DEST"
ok "Systemd service file installed at $SERVICE_DEST"

sudo systemctl daemon-reload
sudo systemctl enable n8n.service
ok "n8n.service enabled — Docker Compose will auto-start on every reboot"

# Docker Compose is already running from Step 5 above;
# the systemd service only needs to be running for reboot recovery.

# =============================================================================
# DONE
# =============================================================================
echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  Setup complete!${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}n8n URL:${NC}  https://${DOMAIN}"
echo ""
echo   "  Useful commands:"
echo   "    View live logs    :  sudo docker compose -f ${INSTALL_DIR}/docker-compose.yml logs -f"
echo   "    Container status  :  sudo docker compose -f ${INSTALL_DIR}/docker-compose.yml ps"
echo   "    Systemd service   :  sudo systemctl status n8n.service"
echo   "    Nginx error log   :  sudo tail -f /var/log/nginx/n8n_error.log"
echo ""
echo -e "  ${YELLOW}Note:${NC} Log out and back in for Docker to work without sudo."
if [[ "$HTTP_CODE" == "000" ]]; then
    echo -e "  ${YELLOW}Note:${NC} DNS has not propagated yet. Visit https://${DOMAIN} in a few minutes."
fi
echo ""
# ── SSH Key Pair ──────────────────────────────────────────────────────────────

# Generate a 4096-bit RSA key pair — Terraform stores both keys in its state file
resource "tls_private_key" "n8n" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Register the public half with AWS
resource "aws_key_pair" "n8n" {
  key_name   = "n8n-key"
  public_key = tls_private_key.n8n.public_key_openssh

  tags = {
    Name = "n8n-key"
  }
}

# Write the private key to a local file so you can SSH in
# The file is created in the terraform/ directory with read-only permissions
resource "local_file" "private_key" {
  content         = tls_private_key.n8n.private_key_pem
  filename        = "${path.module}/n8n-key.pem"
  file_permission = "0400"
}

# ── Security Group ────────────────────────────────────────────────────────────

resource "aws_security_group" "n8n" {
  name        = "n8n-sg"
  description = "n8n server: SSH from your IP only, HTTP/HTTPS from anywhere"
  vpc_id      = data.aws_vpc.default.id

  # SSH — restricted to your IP only
  ingress {
    description = "SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  # HTTP — required for Let's Encrypt verification and to redirect to HTTPS
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS — n8n web interface
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic (needed to pull Docker images, etc.)
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "n8n-sg"
  }
}

# ── EC2 Instance ──────────────────────────────────────────────────────────────

resource "aws_instance" "n8n" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.n8n.key_name
  vpc_security_group_ids = [aws_security_group.n8n.id]

  # Place in the first available subnet of the default VPC
  subnet_id = tolist(data.aws_subnets.default.ids)[0]

  root_block_device {
    volume_size           = 30    # GB — enough for OS, Docker, and n8n data
    volume_type           = "gp3" # Faster and cheaper than gp2
    delete_on_termination = true
  }

  tags = {
    Name     = "n8n-server"
    Domain   = var.n8n_domain
    ManagedBy = "terraform"
  }
}

# ── Elastic IP ────────────────────────────────────────────────────────────────
# A fixed public IP that stays the same even when the instance is stopped/started.
# Required so your DNS record never breaks.

resource "aws_eip" "n8n" {
  instance = aws_instance.n8n.id
  domain   = "vpc"

  tags = {
    Name = "n8n-eip"
  }

  # Ensure instance exists before associating the EIP
  depends_on = [aws_instance.n8n]
}

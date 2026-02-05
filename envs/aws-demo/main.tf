terraform {
  required_version = ">= 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Provider and default tags
provider "aws" {
  region  = "eu-west-2"
  profile = "toni-teleport"

  default_tags {
    tags = {
      "teleport.dev/creator" = "toni.mrsic@goteleport.com"
    }
  }
}

# Networking: VPC, Private Subnet, Break-Glass RDP

resource "aws_vpc" "disclab" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "disclab-vpc"
  }
}

resource "aws_internet_gateway" "disclab" {
  vpc_id = aws_vpc.disclab.id

  tags = {
    Name = "disclab-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.disclab.id
  cidr_block              = "10.42.0.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "disclab-public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.disclab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.disclab.id
  }

  tags = {
    Name = "disclab-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security group for Windows workstation
resource "aws_security_group" "windows_sg" {
  name        = "disclab-publicwindows-sg"
  description = "Security group for Disclab demo environment Windows workstations"
  vpc_id      = aws_vpc.disclab.id

  # # Comment out unless break-glass access needed to bootstrap via direct RDP
  # ingress {
  #   description     = "RDP"
  #   from_port       = 3389
  #   to_port         = 3389
  #   protocol        = "tcp"
  #   security_groups = [aws_security_group.disclab-linux-sg.id]
  # }

  # Allow outbound for Teleport dial out to proxy, Windows updates, etc.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Linux AMI (Amazon Linux 2023)
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}



# Windows AMI (Server 2025)

data "aws_ami" "windows_server_2025" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2025-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# IAM roles
resource "aws_iam_role" "windows_role" {
  name = "disclab-windows-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "disclab-windows-role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.windows_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "windows_profile" {
  name = "disclab-windows-profile"
  role = aws_iam_role.windows_role.name
}

resource "aws_iam_role" "linux_role" {
  name = "disclab-linux-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "disclab-linux-role"
  }
}

resource "aws_iam_role_policy_attachment" "linux_ssm_core" {
  role       = aws_iam_role.linux_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "linux_profile" {
  name = "disclab-linux-profile"
  role = aws_iam_role.linux_role.name
}

resource "aws_security_group" "disclab-linux-sg" {
  name        = "disclab-linux-sg"
  description = "Security group for Linux workstations within the Disclab environment"
  vpc_id      = aws_vpc.disclab.id

  # # Temporary for troubleshooting
  # ingress {
  #   description = "SSH from my local macbook"
  #   from_port   = 22
  #   to_port     = 22
  #   protocol    = "tcp"
  #   cidr_blocks = ["51.7.195.94/32"]
  # }
  #
  # Outbound: Teleport Cloud, Windows RDP, OS updates, etc.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "disclab-linux-sg"
  }
}

# Linux EC2 instance 'Agentless'
resource "aws_instance" "agentless" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.disclab-linux-sg.id]
  iam_instance_profile   = aws_iam_instance_profile.linux_profile.name

  associate_public_ip_address = true

  # Set this if you want SSH with a keypair; otherwise leave null or remove
  key_name = "toni-lab"

  user_data = <<-EOF
  hostnamectl set-hostname agentless
  export KEY=$(curl 'https://ankh-morpork.teleport.sh/webapi/auth/export?type=openssh' | sed "s/cert-authority\ //")
  sudo bash -c "echo \"$KEY\" > /etc/ssh/teleport_openssh_ca.pub"
  sudo bash -c "echo 'TrustedUserCAKeys /etc/ssh/teleport_openssh_ca.pub' >> /etc/ssh/sshd_config"
  sudo bash -c "echo 'HostKey /etc/ssh/agentless' >> /etc/ssh/sshd_config"
  sudo bash -c "echo 'HostCertificate /etc/ssh/agentless-cert.pub' >> /etc/ssh/sshd_config"
  sudo systemctl restart sshd

  EOF


  tags = {
    Name = "disclab-agentless"
  }
}

# Linux EC2 instance 'Magrat'
resource "aws_instance" "magrat" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.disclab-linux-sg.id]
  iam_instance_profile   = aws_iam_instance_profile.linux_profile.name

  associate_public_ip_address = true

  # Set this if you want SSH with a keypair; otherwise leave null or remove
  key_name = "toni-lab"

  user_data = <<-EOF
#!/bin/bash
set -eux

TELEPORT_VERSION="18.6.3"
TELEPORT_DIR="/var/lib/teleport"

# Basic deps
dnf update -y

hostnamectl set-hostname magrat

# Download and install Teleport
mkdir -p /usr/local/teleport-install
cd /usr/local/teleport-install
curl https://cdn.teleport.dev/install.sh | bash -s 18.6.3

# Create Teleport config
cat >/etc/teleport.yaml <<TELEPORTCONF
version: v3
teleport:
  nodename: "magrat"
  data_dir: "/var/lib/teleport"
  join_params:
    method: iam
    token_name: "disclab-iam-token"
  proxy_server: "ankh-morpork.teleport.sh:443"
auth_service:
  enabled: false
proxy_service:
  enabled: false
ssh_service:
  enabled: true
  labels:
    env: "lab"
windows_desktop_service:
  enabled: true
  static_hosts:
    - name: "weatherwax"
      ad: false
      addr: "${aws_instance.windows_workstation.private_ip}:3389"
      labels:
        env: "lab"

TELEPORTCONF

chmod 600 /etc/teleport.yaml

sudo teleport install systemd -o /etc/systemd/system/teleport.service

systemctl daemon-reload
systemctl enable teleport
systemctl start teleport
EOF

  tags = {
    Name = "disclab-magrat"
  }
}

# Windows EC2 Instance
resource "aws_instance" "windows_workstation" {
  ami                    = data.aws_ami.windows_server_2025.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.windows_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.windows_profile.name
  key_name               = "toni-lab"

  associate_public_ip_address = true

  #Teleport Windows Desktop Service Bootstrap
  user_data = <<-EOF
<powershell>
# Set hostname
Rename-Computer -NewName "weatherwax" -Force -Restart:$false

# Enable RDP
Set-ItemProperty "HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server" fDenyTSConnections 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# Download Teleport Windows CA from Teleport Cloud
$TeleportCA = "C:\\Windows\\Temp\\teleport.cer"
Invoke-WebRequest -Uri "https://ankh-morpork.teleport.sh/webapi/auth/export?type=windows" -OutFile $TeleportCA

# Download Teleport Windows Auth Setup tool
$Version = "18.4.1"
$Setup = "C:\\Windows\\Temp\\teleport-windows-auth-setup.exe"
Invoke-WebRequest -Uri "https://cdn.teleport.dev/teleport-windows-auth-setup-v$Version-amd64.exe" -OutFile $Setup

# Install the Teleport Windows Auth integration
Start-Process -FilePath $Setup -ArgumentList "install --cert=$TeleportCA -r" -Wait
</powershell>
  EOF

  tags = {
    Name = "disclab-windows-weatherwax"
  }
}

# Outputs
output "windows_public_ip" {
  description = "Public IP of the Windows workstation"
  value       = aws_instance.windows_workstation.public_ip
}

output "windows_public_dns" {
  description = "Public DNS of the Windows workstation"
  value       = aws_instance.windows_workstation.public_dns
}

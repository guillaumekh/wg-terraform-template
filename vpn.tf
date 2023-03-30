
variable "aws-region" {
  type    = string
  default = "us-east-1"
}

provider "aws" {
  profile    = "default"
  region     = var.aws-region
}

# Find latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu-ami" {
  owners  = ["099720109477"] # Official Ubuntu AMIs
  filter {
    name   = "state"
    values = ["available"]
  }
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64*"]
  }
  most_recent = true
}

# Set firewall rules (i.e. AWS Security Group)
resource "aws_security_group" "security-group" {
  name        = "VPN"
  description = "VPN"

  ingress {
    # SSH
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks  = ["::/0"]
  }

  ingress {
    # Wireguard
    from_port   = 52820
    to_port     = 52820
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks  = ["::/0"]
  }

  egress {
    # Any traffic
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks  = ["::/0"]
  }

  tags = {
    Name = "VPN"
    source = "terraform"
  }
}


# Render a cloud-init config
data "cloudinit_config" "user_data" {
  gzip          = true
  base64_encode = true

  part {
    filename     = "cloud-init.yml"
    content_type = "text/cloud-config"
    content      = templatefile(
      "${path.module}/cloud-init.yml.tpl", {}
    )
  }
}

# Create EC2 instance
resource "aws_instance" "aws-instance" {
  ami           = data.aws_ami.ubuntu-ami.image_id
  instance_type = "t4g.nano"
  vpc_security_group_ids  = [ aws_security_group.security-group.id ]
  ipv6_address_count  = 1
  timeouts {
    create = "5m"
    update = "5m"
    delete = "5m"
  }
  user_data_base64 = data.cloudinit_config.user_data.rendered
  tags = {
    Name = "VPN"
    source = "terraform"
  }
  provisioner "local-exec" {
    command = <<EOT
      # Generate client keypair;
      wg genkey | tee $TMPDIR/client_private_key | wg pubkey > $TMPDIR/client_public_key;
      # Insert client private key and server public IP in WG conf file;
      cp client-wg0.conf $TMPDIR/client-wg0.conf;
      CLIENTPRIVATEKEY=$(cat $TMPDIR/client_private_key);
      sed -i '' "s|client_private_key|$CLIENTPRIVATEKEY|" $TMPDIR/client-wg0.conf;
      sed -i '' "s|server_public_ip|${aws_instance.aws-instance.public_ip}|" $TMPDIR/client-wg0.conf;
      # Download server public key and upload client public key when possible ;
      until scp -o StrictHostKeyChecking=no guillaume@${aws_instance.aws-instance.public_ip}:/etc/wireguard/server_public_key $TMPDIR/server_public_key ; do echo "Awaiting Wireguard server public key..."; sleep 5; done;
      scp -o StrictHostKeyChecking=no $TMPDIR/client_public_key guillaume@${aws_instance.aws-instance.public_ip}:/tmp/;
      # Insert server public key in WG conf file;
      SERVERPUBLICKEY=$(cat $TMPDIR/server_public_key);
      sed -i '' "s|server_public_key|$SERVERPUBLICKEY|" $TMPDIR/client-wg0.conf;
      mv $TMPDIR/client-wg0.conf ~/Desktop/wg0.conf
    EOT
  }
}

# Configure AWS provider for us-west-2 region (Distributed Attacker)
provider "aws" {
  alias  = "west"
  region = "us-west-2"
}

# Fetch the latest Amazon Linux 2023 AMI for us-west-2
data "aws_ami" "amazon_linux_2023_west" {
  provider    = aws.west
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Security Group for the Attacker instance in us-west-2
resource "aws_security_group" "attacker_west_sg" {
  provider    = aws.west
  name        = "attacker-west-sg"
  description = "Security group for distributed attacker instance in us-west-2"

  # Allow outbound traffic to all ports (necessary for attack simulation)
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound UDP for port scanning
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Minimal ingress for management
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project     = "Enterprise-Threat-Pipeline"
    Environment = "Dev"
    ManagedBy   = "Terraform"
    Role        = "Attacker"
  }
}

# Distributed Attacker EC2 Instance in us-west-2
resource "aws_instance" "distributed_attacker" {
  provider              = aws.west
  ami                   = data.aws_ami.amazon_linux_2023_west.id
  instance_type         = "t3.micro"
  vpc_security_group_ids = [aws_security_group.attacker_west_sg.id]
  availability_zone     = "us-west-2a"

  # Attack simulation script
  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y nmap
              
              # Log file for attack simulation
              LOG_FILE="/var/log/attack-simulation.log"
              mkdir -p /var/log
              touch $LOG_FILE
              
              # Function to log attack attempts
              log_attack() {
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
              }
              
              RDS_ENDPOINT="${aws_db_instance.vulnerable_db.endpoint}"
              RDS_HOST=$(echo $RDS_ENDPOINT | cut -d: -f1)
              
              log_attack "Attacker VM initialized in us-west-2"
              log_attack "Target: RDS Database at $RDS_HOST (port 5432)"
              log_attack "Target: Cryptomining pools (ports 3333, 4444)"
              
              # Background continuous attack loop
              (
                while true; do
                  # Attempt to scan RDS database port (5432)
                  nmap -p 5432 $RDS_HOST 2>/dev/null && log_attack "RDS port scan completed" || log_attack "RDS port scan failed"
                  
                  # Attempt to probe cryptomining pool ports (3333, 4444)
                  nmap -p 3333,4444 $RDS_HOST 2>/dev/null && log_attack "Cryptomining pool ports scanned" || log_attack "Cryptomining pool scan failed"
                  
                  # Simulate cryptominer connection attempts with nc
                  (echo "HELLO" | nc -w 1 -v $RDS_HOST 5432 2>&1) >> $LOG_FILE 2>&1 || log_attack "Connection attempt to $RDS_HOST:5432 failed"
                  (echo "STRATUM" | nc -w 1 -v $RDS_HOST 3333 2>&1) >> $LOG_FILE 2>&1 || log_attack "Connection attempt to $RDS_HOST:3333 failed"
                  (echo "STRATUM" | nc -w 1 -v $RDS_HOST 4444 2>&1) >> $LOG_FILE 2>&1 || log_attack "Connection attempt to $RDS_HOST:4444 failed"
                  
                  # Wait before next attack cycle
                  sleep 60
                done
              ) &
              
              # CPU stress loop for persistence
              while true; do :; done &
              EOF
  )

  tags = {
    Name        = "Distributed-Attacker-West"
    Project     = "Enterprise-Threat-Pipeline"
    Environment = "Dev"
    ManagedBy   = "Terraform"
    Role        = "Attacker"
  }
}

# Output the attacker instance details
output "distributed_attacker_instance_id" {
  description = "Instance ID of the distributed attacker in us-west-2"
  value       = aws_instance.distributed_attacker.id
}

output "distributed_attacker_public_ip" {
  description = "Public IP address of the distributed attacker"
  value       = aws_instance.distributed_attacker.public_ip
}

output "distributed_attacker_private_ip" {
  description = "Private IP address of the distributed attacker"
  value       = aws_instance.distributed_attacker.private_ip
}

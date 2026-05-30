# --- IAM Resources for EC2 S3 Upload ---

# IAM Role for EC2 instances to assume
resource "aws_iam_role" "ec2_s3_upload_role" {
  name = "ec2-s3-upload-role"

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
    Project     = "Enterprise-Threat-Pipeline"
    Environment = "Dev"
    ManagedBy   = "Terraform"
  }
}

# IAM Policy for S3 PutObject permissions
resource "aws_iam_role_policy" "ec2_s3_upload_policy" {
  name   = "ec2-s3-upload-policy"
  role   = aws_iam_role.ec2_s3_upload_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.log_bucket.arn,
          "${aws_s3_bucket.log_bucket.arn}/*"
        ]
      }
    ]
  })
}

# IAM Instance Profile for EC2 instances
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2-s3-upload-instance-profile"
  role = aws_iam_role.ec2_s3_upload_role.name
}

# --- Web Server Launch Template ---

# 1. Create a Launch Template for the Web Servers
resource "aws_launch_template" "web_server_lt" {
  name_prefix            = "web-server-"
  image_id               = "ami-0c101f26f147fa7fd" # Amazon Linux 2023 AMI
  instance_type          = "t3.micro"
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }

  # This is the "Attacker" (Cryptojacker simulation)
  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              mkdir -p /var/log/threat-sim/
              cat > /var/log/threat-sim/endpoint_telemetry.json <<'INNEREOF'
              {"event_type": "Process Creation", "process_name": "xmrig.exe", "command_line": "./xmrig -o pool.minexmr.com:443 -u admin", "severity": "High", "mitre_tactic": "T1496"}
              INNEREOF
              
              # Install AWS CLI and upload the endpoint telemetry to S3
              yum install -y aws-cli
              aws s3 cp /var/log/threat-sim/endpoint_telemetry.json s3://${aws_s3_bucket.log_bucket.bucket}/endpoint-logs/endpoint_telemetry.json --region us-east-1
              
              while true; do :; done &
              EOF
  )

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web_sg.id]
  }

  tags = {
    Name        = "Cryptojacker-Sim"
    Project     = "Enterprise-Threat-Pipeline"
    Environment = "Dev"
    ManagedBy   = "Terraform"
    Role        = "Attacker"
  }
}

# 2. Security Group for the Web Servers
resource "aws_security_group" "web_sg" {
  name   = "web-server-sg"
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project     = "Enterprise-Threat-Pipeline"
    Environment = "Dev"
    ManagedBy   = "Terraform"
  }
}

# 3. Create the Auto-Scaling Group
resource "aws_autoscaling_group" "asg" {
  vpc_zone_identifier = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  desired_capacity    = 2
  max_size            = 3
  min_size            = 1

  launch_template {
    id      = aws_launch_template.web_server_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Project"
    value               = "Enterprise-Threat-Pipeline"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "Dev"
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "Terraform"
    propagate_at_launch = true
  }
}
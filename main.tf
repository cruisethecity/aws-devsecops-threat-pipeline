# --- VPC and Networking ---

# 1. Create the VPC
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    {
      Name = "Threat-Pipeline-VPC"
    },
    {
      Project     = "Enterprise-Threat-Pipeline"
      Environment = "Dev"
      ManagedBy   = "Terraform"
    }
  )
}

# 2. Create the Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = merge(
    {
      Name = "Threat-Pipeline-IGW"
    },
    {
      Project     = "Enterprise-Threat-Pipeline"
      Environment = "Dev"
      ManagedBy   = "Terraform"
    }
  )
}

# 3. Create Public Subnet 1 (us-east-1a)
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = merge(
    {
      Name = "Public-Subnet-1"
    },
    {
      Project     = "Enterprise-Threat-Pipeline"
      Environment = "Dev"
      ManagedBy   = "Terraform"
    }
  )
}

# 4. Create Public Subnet 2 (us-east-1b)
resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = merge(
    {
      Name = "Public-Subnet-2"
    },
    {
      Project     = "Enterprise-Threat-Pipeline"
      Environment = "Dev"
      ManagedBy   = "Terraform"
    }
  )
}

# 5. Create a Route Table to send traffic to the Internet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Project     = "Enterprise-Threat-Pipeline"
    Environment = "Dev"
    ManagedBy   = "Terraform"
  }
}

# 6. Associate Subnets with the Route Table
resource "aws_route_table_association" "public_1_assoc" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_2_assoc" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

# --- Security and Database ---

# 1. Create a Security Group that allows DB traffic from anywhere (Vulnerable!)
resource "aws_security_group" "db_sg" {
  name        = "vulnerable-db-sg"
  description = "Allow port 5432 from anywhere"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # This is the vulnerability!
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

# 2. Create the DB Subnet Group (Required to fix the "different VPC" error)
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "threat-db-subnet-group"
  subnet_ids = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]

  tags = merge(
    {
      Name = "My Threat DB Subnet Group"
    },
    {
      Project     = "Enterprise-Threat-Pipeline"
      Environment = "Dev"
      ManagedBy   = "Terraform"
    }
  )
}

# 3. Create the RDS Database (Vulnerable!)
resource "aws_db_instance" "vulnerable_db" {
  allocated_storage = 20
  db_name           = "threatdb"
  engine            = "postgres"
  engine_version    = "15"
  instance_class    = "db.t3.micro"
  username          = "dbadmin"
  password          = var.db_password

  # Security vulnerabilities:
  publicly_accessible = true
  storage_encrypted   = false

  # Linking to the Subnet Group created above
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name

  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  tags = {
    Project     = "Enterprise-Threat-Pipeline"
    Environment = "Dev"
    ManagedBy   = "Terraform"
  }
}
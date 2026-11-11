resource "aws_vpc" "main" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {

    Name = "shopzany-vpc"
  }

}

# create a public subnet
resource "aws_subnet" "public_1" {
  vpc_id             = aws_vpc.main.id
  availability_zone = "us-east-1a"
  cidr_block         = "10.0.1.0/24"
  tags= {
    Name = "zany-public-1a"
  }
}
# create another public subnet
resource "aws_subnet" "public_2" {
  vpc_id             = aws_vpc.main.id
  availability_zone = "us-east-1b"
  cidr_block         = "10.0.2.0/24"
   tags = {
    Name = "zany-public-1b"
  }
}
# create an igw
resource "aws_internet_gateway" "igw"{
    vpc_id = aws_vpc.main.id
    tags ={
        Name = "zany-igw"
    }
}
#create a public_route_table
resource "aws_route_table" "public" {
    vpc_id = aws_vpc.main.id
    route{
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }
    tags={
        Name ="public-rt"
    }
}
#create a route table association
resource "aws_route_table_association" "public_1" {
    subnet_id = aws_subnet.public_1.id
    route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
    subnet_id = aws_subnet.public_2.id
    route_table_id = aws_route_table.public.id
}

#create a private subnet
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "us-east-1a"
  cidr_block        = "10.0.3.0/24"

  tags = {
    Name = "zany-private-1"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "us-east-1b"
  cidr_block        = "10.0.4.0/24"

  tags = {
    Name = "zany-private-2"
  }
}

# ---------- NAT Gateway ----------
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "zany-nat-eip" }
}
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id # NAT lives in a PUBLIC subnet

  tags = { Name = "zany-nat" }

  depends_on = [aws_internet_gateway.igw]
}
# ---------- Private DB subnets ----------
resource "aws_subnet" "private_db_1" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "us-east-1a"
  cidr_block        = "10.0.21.0/24"

  tags = { Name = "zany-private-db-1a" }
}

resource "aws_subnet" "private_db_2" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "us-east-1b"
  cidr_block        = "10.0.22.0/24"

  tags = { Name = "zany-private-db-1b" }
}



# ---------- Private app route table (outbound via NAT) ----------
resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = { Name = "zany-private-app-rt" }
}

resource "aws_route_table_association" "private_app_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_app.id
}

resource "aws_route_table_association" "private_app_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private_app.id
}

# ---------- DB route table (no internet route at all) ----------
resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "zany-private-db-rt" }
}

resource "aws_route_table_association" "private_db_1" {
  subnet_id      = aws_subnet.private_db_1.id
  route_table_id = aws_route_table.private_db.id
}

resource "aws_route_table_association" "private_db_2" {
  subnet_id      = aws_subnet.private_db_2.id
  route_table_id = aws_route_table.private_db.id
}

# ---------- ALB: open to the internet on web ports only ----------
resource "aws_security_group" "alb" {
  name        = "zany-alb-sg"
  description = "Allow HTTP and HTTPS from the internet"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "zany-alb-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from anywhere"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_all_out" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------- App servers: only accept traffic from the ALB ----------
resource "aws_security_group" "app" {
  name        = "zany-app-sg"
  description = "Allow HTTP from the ALB only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "zany-app-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "HTTP from ALB"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_all_out" {
  security_group_id = aws_security_group.app.id
  description       = "Allow all outbound (via NAT)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------- Database: only accept MySQL from the app servers ----------
resource "aws_security_group" "db" {
  name        = "zany-db-sg"
  description = "Allow MySQL from the app servers only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "zany-db-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "MySQL from app servers"
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
}
# ---------- Application Load Balancer ----------
resource "aws_lb" "main" {
  name               = "zany-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = { Name = "zany-alb" }
}

# ---------- Target group (where the ALB sends traffic) ----------
resource "aws_lb_target_group" "app" {
  name     = "zany-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health.php"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 3600
    enabled         = true
  }

  tags = { Name = "zany-app-tg" }
}

# ---------- Listener (port 80 -> target group) ----------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ---------- Output ----------
output "alb_dns_name" {
  description = "Public URL of the load balancer"
  value       = aws_lb.main.dns_name
}


resource "aws_db_subnet_group" "main" {
  name       = "zany-db-subnets"
  subnet_ids = [aws_subnet.private_db_1.id, aws_subnet.private_db_2.id]
}

resource "aws_db_instance" "main" {
  identifier             = "shopzany-db"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  storage_encrypted      = true
  db_name                = "shopzany"
  username               = "admin"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false # single-AZ to save cost; Multi-AZ is a growth item
  skip_final_snapshot    = true
}
# ---------- IAM role so admins can connect via SSM (no SSH) ----------
resource "aws_iam_role" "app" {
  name = "zany-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "zany-app-profile"
  role = aws_iam_role.app.name
}

# ---------- Latest Ubuntu 24.04 AMI (published by Canonical) ----------
data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# ---------- Launch template ----------
resource "aws_launch_template" "app" {
  name_prefix   = "zany-app-"
  image_id      = data.aws_ssm_parameter.ubuntu.value
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  metadata_options {
    http_tokens = "required" # enforce IMDSv2
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e
    apt-get update -y
    apt-get install -y apache2 php libapache2-mod-php php-mysql git

    rm -rf /var/www/html/*
    git clone https://github.com/chukkyzany/shopzany-app.git /tmp/shopzany-app
    cp -r /tmp/shopzany-app/* /var/www/html/

    cat > /var/www/html/config.php <<'PHP'
    <?php
    define('DB_HOST', '${aws_db_instance.main.address}');
    define('DB_NAME', 'shopzany');
    define('DB_USER', 'admin');
    define('DB_PASS', '${var.db_password}');
    PHP

    chown -R www-data:www-data /var/www/html
    systemctl enable --now apache2
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "zany-app" }
  }
}

# ---------- Auto Scaling Group ----------
resource "aws_autoscaling_group" "app" {
  name                      = "zany-app-asg"
  min_size                  = 2
  max_size                  = 4
  desired_capacity          = 2
  vpc_zone_identifier       = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "zany-app"
    propagate_at_launch = true
  }
}
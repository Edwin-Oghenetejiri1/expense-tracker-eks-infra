locals {
  common_tags = {
    Name = "${var.vpc_name}-${var.env}"
  }
}

# This resource creates the vpc
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    local.common_tags,
    {
      Environment                                               = "production"
      Owner                                                     = "devops-team"
      "${format("kubernetes.io/cluster/%s", var.cluster_name)}" = "shared"
    }
  )
}

# This will create both public and private subnets
resource "aws_subnet" "private-subnets" {
  count                   = length(var.private_subnets_cidr)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnets_cidr[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(
    {
      "Name" = "app-subnet-${count.index + 1}-${var.env}"
    },
    var.create_for_eks ? {
      "kubernetes.io/role/internal-elb"           = "1"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
      "karpenter.sh/discovery"                    = var.cluster_name
    } : {}
  )
}

resource "aws_subnet" "public-subnets" {
  count                   = length(var.public_subnets_cidr)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets_cidr[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    {
      "Name" = "public-subnet-${count.index + 1}-${var.env}"
    },
    var.create_for_eks ? {
      "kubernetes.io/role/elb"                    = "1"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
      "karpenter.sh/discovery"                    = var.cluster_name
    } : {}
  )
}

# This will create the internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-igw-${var.env}"
  }
}

# One EIP per AZ for high availability
resource "aws_eip" "nat-eip" {
  count = length(var.public_subnets_cidr)

  tags = {
    Name = "${var.vpc_name}-eip-${count.index + 1}-${var.env}"
  }
}

# One NAT Gateway per AZ for high availability
# If one AZ goes down the other AZ can still reach the internet
resource "aws_nat_gateway" "ngw" {
  count         = length(var.public_subnets_cidr)
  allocation_id = aws_eip.nat-eip[count.index].id
  subnet_id     = aws_subnet.public-subnets[count.index].id

  tags = {
    Name        = "${var.vpc_name}-ngw-${count.index + 1}-${var.env}"
    Environment = var.env
  }

  depends_on = [aws_internet_gateway.igw]
}

# Public route table — single one shared across all public subnets
resource "aws_route_table" "pub-rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "${var.vpc_name}-public-rt-${var.env}"
    Environment = var.env
  }
}

# One private route table per AZ
# Each AZ routes through its own NAT Gateway
resource "aws_route_table" "priv-rt" {
  count  = length(var.private_subnets_cidr)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw[count.index].id
  }

  tags = {
    Name        = "${var.vpc_name}-private-rt-${count.index + 1}-${var.env}"
    Environment = var.env
  }
}

# Associate public subnets with the public route table
resource "aws_route_table_association" "pub" {
  count          = length(aws_subnet.public-subnets)
  subnet_id      = aws_subnet.public-subnets[count.index].id
  route_table_id = aws_route_table.pub-rt.id
}

# Associate each private subnet with its own route table
resource "aws_route_table_association" "priv" {
  count          = length(aws_subnet.private-subnets)
  subnet_id      = aws_subnet.private-subnets[count.index].id
  route_table_id = aws_route_table.priv-rt[count.index].id
}
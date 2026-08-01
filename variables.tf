variable "aws_region" {
  type        = string
  description = "The region where EC2 instance running"
  default     = "eu-north-1"
}

variable "instance_type" {
  type        = string
  description = "The type of the EC2 instance"
  default     = "t3.micro"
}

variable "vpc_cidr" {
  type = string
  description = "Cidr block of the vpc"
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type = string
  description = "Cidr block of the public subnet"
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type = string
  description = "Cidr block of the private subnet"
  default = "10.0.2.0/24"
}
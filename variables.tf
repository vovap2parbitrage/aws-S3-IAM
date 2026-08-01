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
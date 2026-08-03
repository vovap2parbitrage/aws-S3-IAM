output "ec2_public_ip" {
  description = "The public IP of the EC2 public instance"
  value       = aws_instance.public_instance.public_ip
}
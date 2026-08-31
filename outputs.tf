output "ec2_public_ip" {
  description = "The public IP of the EC2 public instance"
  value       = aws_instance.public_instance.public_ip
}

output "app_bucket_name" {
  description = "The name of the app bucket"
  value       = aws_s3_bucket.app_bucket.id
}

output "replicated_bucket_name" {
  description = "The name of the app replicated bucket"
  value       = aws_s3_bucket.replicated_app_bucket.id
}
variable "game_state" {
  description = "Determines if the game is running or not. Values: running, stopped."
  type        = string
  default     = "stopped"
}

output "minecraft_server_public_ip" {
  value = [for i in aws_instance.minecraft-server : i.public_ip]
  description = "The public IP address of the minecraft server."
}

provider "aws" {
  region  = "us-east-2"  # You can change this to your desired AWS region
  default_tags {
    tags = {
      Name = "minecraft-server"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "minecraft_server_logs_ownership_controls" {
  bucket = aws_s3_bucket.minecraft_server_terraform_state_logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "minecraft_server_state_logs_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.minecraft_server_logs_ownership_controls]
  bucket = aws_s3_bucket.minecraft_server_terraform_state_logs.id
  acl    = "log-delivery-write"
}

resource "aws_s3_bucket" "minecraft_server_terraform_state_logs" {
  bucket = "minecraft-server-terraform-state-bucket-logs"
}

resource "aws_s3_bucket_ownership_controls" "minecraft_server_terraform_state_ownership_controls" {
  bucket = aws_s3_bucket.minecraft_server_terraform_state_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "minecraft_server_bucket_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.minecraft_server_terraform_state_ownership_controls]
  bucket = aws_s3_bucket.minecraft_server_terraform_state_bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "minecraft_server_terraform_state_versioning" {
  bucket = aws_s3_bucket.minecraft_server_terraform_state_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_kms_key" "minecraft_server_terraform_state_kms_key" {
  description             = "This key is used to encrypt bucket objects"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "minecraft_server_terraform_encryption_config" {
  bucket = aws_s3_bucket.minecraft_server_terraform_state_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.minecraft_server_terraform_state_kms_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket" "minecraft_server_terraform_state_bucket" {
  bucket = "minecraft-server-terraform-state-bucket"
}

resource "aws_s3_bucket_logging" "minecraft_server_terraform_state_logging" {
  bucket = aws_s3_bucket.minecraft_server_terraform_state_bucket.id

  target_bucket = aws_s3_bucket.minecraft_server_terraform_state_logs.id
  target_prefix = "log/"
}

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.minecraft_server_terraform_state_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Deny"
        Action    = "s3:*"
        Resource  = "${aws_s3_bucket.minecraft_server_terraform_state_bucket.arn}/*"
        Condition = {
          Bool = {
            "aws:SecureTransport": "false"
          }
        }
        Principal = "*"
      }
    ]
  })
}

resource "aws_dynamodb_table" "minecraft_server_terraform_lock_table" {
  name           = "minecraft-server-terraform-lock-table"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

terraform {
  backend "s3" {
    region = "us-east-2"
    bucket = "minecraft-server-terraform-state-bucket"
    key    = "states/minecraft-server/terraform.tfstate"
    dynamodb_table = "minecraft-server-terraform-lock-table"
    encrypt = true
  }
}

resource "aws_instance" "minecraft-server" {
  count         = var.game_state == "running" ? 1 : 0
  ami           = "ami-01936e31f56bdacde"  # Focal Fossa | 20.04 | LTS | amd64 | hvm:ebs-ssd
  instance_type = "t2.micro"
}

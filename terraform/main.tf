variable "vpc_id" {
  description = "The ID of the AWS VPC"
  type        = string
}

variable "game_state" {
  description = "Determines if the game is running or not. Values: running, stopped."
  type        = string
  default     = "stopped"
}

output "minecraft_server_public_ip" {
  value = [for i in aws_instance.minecraft-server : i.public_ip]
  description = "The public IP address of the minecraft server."
}

output "minecraft_server_instance_ids" {
  value = [for i in aws_instance.minecraft-server : i.id]
  description = "The instance ID(s) of the Minecraft server."
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
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name
  vpc_security_group_ids = [aws_security_group.allow_https_outbound.id]

  user_data = <<-EOF
              #!/bin/bash
              # Update package index
              sudo apt-get update

              # Install the SSM Agent
              sudo snap install amazon-ssm-agent --classic

              # Enable the SSM Agent to start on boot
              sudo systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service

              # Start the SSM Agent service
              sudo systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service
              EOF
}

resource "aws_iam_role" "ssm_role" {
  name = "ssm_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "ssm_instance_profile"
  role = aws_iam_role.ssm_role.name
}


######################
## Slack App Infra  ##
######################

variable "slack_token" {
  description = "Slack Bot User OAuth Token"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "The GitHub token for Secrets Manager"
  type        = string
  sensitive   = true  # This ensures Terraform doesn't print the value in outputs
}

resource "aws_secretsmanager_secret" "github_token_secret" {
  name = "github_token"
  description = "Secret for GitHub Token"
}

resource "aws_secretsmanager_secret_version" "github_token_secret_version" {
  secret_id     = aws_secretsmanager_secret.github_token_secret.id
  secret_string = "{\"GITHUB_TOKEN\":\"${var.github_token}\"}"
}

resource "aws_lambda_function" "minecraft_bot" {
  function_name    = "minecraftBot"
  role             = aws_iam_role.lambda_role.arn
  handler          = "minecraftBot.handler"  # <FileName without extension>.<Exported function name>
  runtime          = "nodejs16.x"
  filename         = "../dist/minecraftBot.zip"
  source_code_hash = filebase64sha256("../dist/minecraftBot.zip")  # Detect changes to the source
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_apigatewayv2_api" "minecraft_bot_api" {
  name          = "minecraftBotApi"
  protocol_type = "HTTP"
  target        = aws_lambda_function.minecraft_bot.arn
}

resource "aws_lambda_permission" "api_gateway" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.minecraft_bot.function_name
  principal     = "apigateway.amazonaws.com"

  // Source ARN for the permission. In this case, allow any path on the API Gateway
  source_arn = "${aws_apigatewayv2_api.minecraft_bot_api.execution_arn}/*/*"
}

resource "aws_cloudwatch_log_group" "minecraft_bot_lambda_log_group" {
  name = "/aws/lambda/minecraft-bot-lambda-function"
}

resource "aws_iam_policy" "minecraft_bot_lambda_logging" {
  name        = "MinecraftBotLambdaLogging"
  description = "IAM policy for logging from Minecraft Bot Lambda"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*",
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  policy_arn = aws_iam_policy.minecraft_bot_lambda_logging.arn
  role       = aws_iam_role.lambda_role.name
}

resource "aws_iam_role_policy_attachment" "secrets_manager_access" {
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
  role       = aws_iam_role.lambda_role.name
}

####################################################
# Create the S3 Bucket for Minecraft Server Ansible
####################################################

resource "aws_s3_bucket" "gtempus_minecraft_server_ansible" {
  bucket = "gtempus-minecraft-server-ansible"
}

# IAM Policy for S3 Bucket Access
resource "aws_iam_policy" "s3_read_policy" {
  name        = "s3ReadPolicy"
  description = "Policy to allow EC2 instance to read specific S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["s3:GetObject", "s3:ListBucket"],
        Effect   = "Allow",
        Resource = [
          aws_s3_bucket.gtempus_minecraft_server_ansible.arn,
          "${aws_s3_bucket.gtempus_minecraft_server_ansible.arn}/*"
        ],
      },
    ],
  })
}

# Attach the Policy to the IAM Role
resource "aws_iam_role_policy_attachment" "s3_read_policy_attachment" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = aws_iam_policy.s3_read_policy.arn
}

###################
# Instance Connect
###################
resource "aws_iam_policy" "ec2_instance_connect_policy" {
  name        = "ec2_instance_connect_policy"
  description = "Policy to allow EC2 Instance Connect"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "ec2-instance-connect:SendSSHPublicKey",
        Resource = "arn:aws:ec2:us-east-2:*:instance/*",
        Condition = {
          StringEquals = {
            "ec2:osuser" = "ubuntu"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_instance_connect_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = aws_iam_policy.ec2_instance_connect_policy.arn
}

resource "aws_security_group" "allow_https_outbound" {
  name        = "allow_https_outbound"
  description = "Security group to allow outbound HTTPS traffic"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_https_outbound"
  }
}


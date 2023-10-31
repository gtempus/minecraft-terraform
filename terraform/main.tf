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
  function_name = "minecraftBot"
  role          = aws_iam_role.lambda_role.arn
  handler       = "minecraftBot.handler"  # <FileName without extension>.<Exported function name>
  runtime       = "nodejs16.x"
  filename      = "../dist/minecraftBot.zip"
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


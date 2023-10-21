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
}

resource "aws_instance" "minecraft-server" {
  count         = var.game_state == "running" ? 1 : 0
  ami           = "ami-01936e31f56bdacde"  # Focal Fossa | 20.04 | LTS | amd64 | hvm:ebs-ssd
  instance_type = "t2.micro"

  tags = {
    Name = "minecraft-server"
  }
}

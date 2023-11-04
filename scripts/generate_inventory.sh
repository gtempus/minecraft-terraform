#!/bin/bash

# Fetch the output from Terraform
output=$(terraform output -json)

# Parse the output with jq and create the inventory
echo "[minecraft_servers]" > ../ansible/inventory
echo "$output" | jq -r '.minecraft_server_public_ip.value[]' | while read ip; do
  echo "minecraft_server ansible_host=${ip} ansible_user=ubuntu" >> ../ansible/inventory
done

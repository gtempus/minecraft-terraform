# Restoring Backups
Here are steps to get a backed up worlds folder off of s3 and into the server.

1. Start an SSM Session with the minecraft server
1. Install the awscli `pip3 install awscli --upgrade --user`
1. Verify `aws aws --version`
1. Configure aws with `aws configure`.
    1. You don't need to add credential information since you're in a SSM session.
    1. You will need to set the region `us-east-2`
1. Stop the server: `sudo systemctl stop minecraft.service`
1. Check the logs: `sudo journalctl -u minecraft.service`
1. Download the desired backup file from s3.
    1. `aws s3 cp s3://tempus-minecraft-server-ansible/backups/<backup.zip> /tmp`
1. Unzip the backup to the `tmp` dir: `unzip <backup.zip>`
1. Remove the corrupt `worlds` folder in the server directory:
    1. `sudo rm -rf /mnt/ebs_volume/minecraft/worlds`
1. Move the `worlds` directory in the `tmp` folder to the minecraft server:
    1. `sudo mv ./worlds /mnt/ebs_volume/minecraft/`
1. Change the `worlds` owner:group back to `minecraft`:
    1. `sudo chown -R minecraft:minecraft /mnt/ebs_volume/minecraft/worlds`
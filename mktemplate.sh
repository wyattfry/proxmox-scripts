#!/bin/bash
set -euxo pipefail

# Function to find the next available VM ID above 9000
find_next_template_id() {
    ID=9000
    while qm status $ID &>/dev/null; do
        ((ID++))
    done
    echo $ID
}

TEMPLATE_ID=$(find_next_template_id)
TEMPLATE_NAME="ubuntu-template"
IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
IMAGE_FILE="ubuntu-cloudimg.qcow2"
STORAGE="nfs-storage"
SSH_KEY_FILE="$HOME/.ssh/authorized_keys"

echo "Using template ID: $TEMPLATE_ID"

# Download Ubuntu Cloud Image if not already downloaded
if [ ! -f "$IMAGE_FILE" ]; then
    echo "Downloading Ubuntu cloud image..."
    wget -O "$IMAGE_FILE" "$IMAGE_URL"
fi

virt-customize -a "$IMAGE_FILE" \
    --install qemu-guest-agent,avahi-daemon \
    --firstboot-command "systemctl enable qemu-guest-agent"

# Create a new VM template
echo "Creating Proxmox VM template..."
qm create "$TEMPLATE_ID" --name $TEMPLATE_NAME --memory 2048 --net0 virtio,bridge=vmbr0

# Import the disk properly for NFS storage
echo "Importing disk to $STORAGE..."
qm importdisk "$TEMPLATE_ID" "$IMAGE_FILE" "$STORAGE"

# Find the actual disk filename
DISK_PATH=$(ls /mnt/pve/$STORAGE/images/"$TEMPLATE_ID"/ | grep '\.raw$' | head -n 1)

# Ensure the disk path exists
if [[ -z "$DISK_PATH" ]]; then
    echo "Error: Imported disk file not found in /mnt/pve/$STORAGE/images/$TEMPLATE_ID/"
    exit 1
fi

# Attach disk properly using full filename
qm set "$TEMPLATE_ID" --scsihw virtio-scsi-pci --scsi0 "$STORAGE:$TEMPLATE_ID/$DISK_PATH"

# Set boot options
qm set "$TEMPLATE_ID" --boot c --bootdisk scsi0

# Create Cloud-Init drive
qm set "$TEMPLATE_ID" --ide2 "$STORAGE:cloudinit"
qm set "$TEMPLATE_ID" --serial0 socket --vga serial0

# Configure Cloud-Init settings
qm set "$TEMPLATE_ID" --searchdomain local --nameserver 1.1.1.1
qm set "$TEMPLATE_ID" --ipconfig0 ip=dhcp
qm set "$TEMPLATE_ID" --sshkeys "$SSH_KEY_FILE"

# Ensure correct path for Cloud-Init user-data file
CLOUD_INIT_FILE="/var/lib/qemu-server/$TEMPLATE_ID.cloud-init"

echo "Setting up cloud-init user data at $CLOUD_INIT_FILE..."
cat <<EOF > "$CLOUD_INIT_FILE"
#cloud-config
preserve_hostname: false
disable_root: false
locale: en_US.UTF-8
timezone: UTC
users:
  - name: wyatt
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    ssh_authorized_keys:
      - $(cat "$SSH_KEY_FILE")
runcmd:
  - hostnamectl set-hostname $TEMPLATE_NAME --pretty
EOF

# Convert to template
qm template "$TEMPLATE_ID"

echo "Template $TEMPLATE_NAME (ID: $TEMPLATE_ID) created successfully!"

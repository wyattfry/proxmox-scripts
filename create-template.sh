#!/bin/bash

# Variables
TEMPLATE_ID=9001
TEMPLATE_NAME="ubuntu-template"
IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
IMAGE_FILE="ubuntu-cloudimg.qcow2"

# Download Ubuntu Cloud Image
if [ ! -f "$IMAGE_FILE" ]; then
    echo "Downloading Ubuntu cloud image..."
    wget -O "$IMAGE_FILE" "$IMAGE_URL"
fi

# Create a new VM
echo "Creating Proxmox VM template..."
qm create $TEMPLATE_ID --name $TEMPLATE_NAME --memory 2048 --net0 virtio,bridge=vmbr0

# Import the disk
echo "Importing disk..."
qm importdisk $TEMPLATE_ID "$IMAGE_FILE" local-lvm

# Attach disk to VM
echo "Configuring disk..."
qm set $TEMPLATE_ID --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-$TEMPLATE_ID-disk-0

# Set boot options
qm set $TEMPLATE_ID --boot c --bootdisk scsi0

# Create Cloud-Init drive
echo "Creating Cloud-Init drive..."
qm set $TEMPLATE_ID --ide2 local-lvm:cloudinit
qm set $TEMPLATE_ID --serial0 socket --vga serial0

# Configure Cloud-Init
echo "Configuring Cloud-Init settings..."
qm set $TEMPLATE_ID --cipassword "password"
qm set $TEMPLATE_ID --ciuser "wyatt"
qm set $TEMPLATE_ID --searchdomain local --nameserver 1.1.1.1
qm set $TEMPLATE_ID --ipconfig0 ip=dhcp

# Convert to template
echo "Converting VM to template..."
qm template $TEMPLATE_ID

echo "Template created successfully!"


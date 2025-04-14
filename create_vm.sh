#!/bin/bash
set -e

# Check parameters
if [ $# -ne 4 ]; then
    echo "Usage: $0 <vm_id> <vm_name> <ip_address> <ssh_key_file>"
    echo "Example: $0 109 ubuntu-vm 10.0.0.109/24 /root/.ssh/id_rsa.pub"
    exit 1
fi

# Variables
TEMPLATE_ID=9006
NEW_VMID=$1
VM_NAME=$2
IP_ADDRESS=$3
SSH_KEY_FILE=$4

# Check if template exists and is stopped
echo "Checking template status..."
if ! qm status $TEMPLATE_ID | grep -q "status: stopped"; then
    echo "Error: Template $TEMPLATE_ID must exist and be in stopped state"
    exit 1
fi

# Check if NFS storage is available
echo "Checking NFS storage..."
if [ ! -d "/mnt/pve/nfs-storage" ]; then
    echo "Error: NFS storage not available at /mnt/pve/nfs-storage"
    exit 1
fi

# Check if target VM already exists
echo "Checking if target VM exists..."
if qm status $NEW_VMID &>/dev/null; then
    echo "Error: VM $NEW_VMID already exists"
    exit 1
fi

# Validate IP address format
if ! echo $IP_ADDRESS | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$'; then
    echo "Error: Invalid IP address format. Must be in format: x.x.x.x/xx"
    exit 1
fi

# Validate SSH key file
if [ ! -f "$SSH_KEY_FILE" ]; then
    echo "Error: SSH key file $SSH_KEY_FILE not found"
    exit 1
fi

# Read SSH key content
SSH_KEY=$(cat "$SSH_KEY_FILE")

# Clone the VM
echo "Cloning VM..."
qm clone $TEMPLATE_ID $NEW_VMID --name $VM_NAME

# Set boot order to scsi0
echo "Setting boot order..."
qm set $NEW_VMID --boot order=scsi0

# Configure static IP
echo "Configuring static IP..."
qm set $NEW_VMID --ipconfig0 ip=$IP_ADDRESS,gw=10.0.0.1

# Configure SSH key
echo "Configuring SSH key..."
qm set $NEW_VMID --sshkeys "$SSH_KEY_FILE"

# Ensure QEMU Guest Agent is enabled
echo "Ensuring QEMU Guest Agent is enabled..."
qm set $NEW_VMID --agent enabled=1

echo "VM creation completed successfully"

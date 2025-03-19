#!/bin/bash

# Parameters
VM_ID=$1
HOSTNAME=$2
RAM_SIZE=$3
DISK_SIZE=$4

# Check for required arguments
if [ -z "$VM_ID" ] || [ -z "$HOSTNAME" ] || [ -z "$RAM_SIZE" ] || [ -z "$DISK_SIZE" ]; then
    echo "Usage: $0 <vm_id> <hostname> <ram_size_mb> <disk_size_gb>"
    exit 1
fi

TEMPLATE_ID=9001

# Clone the template
echo "Cloning template to create new VM..."
qm clone $TEMPLATE_ID $VM_ID --name $HOSTNAME --full true

# Configure VM settings
echo "Setting VM parameters..."
qm set $VM_ID --memory $RAM_SIZE
qm set $VM_ID --ipconfig0 ip=dhcp
qm set $VM_ID --ciuser wyatt --cipassword "password"

# Resize disk
echo "Resizing disk to ${DISK_SIZE}G..."
qm resize $VM_ID scsi0 ${DISK_SIZE}G

# Start the VM
echo "Starting VM..."
qm start $VM_ID

echo "VM $HOSTNAME ($VM_ID) created successfully!"


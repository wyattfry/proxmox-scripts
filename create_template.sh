#!/bin/bash

# Error handling
set -euo pipefail

# Create log file with timestamp
LOG_FILE="template_creation_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "Starting template creation process at $(date)"

# Cleanup function
cleanup() {
    local exit_code=$?
    echo "Cleaning up temporary files..."
    rm -f jammy-server-cloudimg-amd64.img "vm-${VM_ID}-disk-0.qcow2"
    if [ $exit_code -ne 0 ]; then
        echo "Script failed with exit code $exit_code"
    fi
    exit $exit_code
}

# Set trap for cleanup
trap cleanup EXIT

# Script variables
VM_ID=$1
STORAGE="nfs-storage"
MEMORY=2048
CORES=2
DISK_SIZE="10G"
TEMPLATE_NAME="$2"
IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"

# Validate storage availability
if ! pvesm status | grep -q "^${STORAGE}"; then
    echo "Error: Storage '${STORAGE}' not found"
    exit 1
fi

# Check if virt-customize is installed
if ! command -v virt-customize >/dev/null 2>&1; then
    echo "Installing libguestfs-tools..."
    apt-get update && apt-get install -y libguestfs-tools
fi

echo "Environment setup completed successfully"

# Download Ubuntu cloud image
echo "Checking for Ubuntu cloud image..."
if [ ! -f "jammy-server-cloudimg-amd64.img" ]; then
    echo "Downloading Ubuntu cloud image..."
    wget "${IMAGE_URL}" -O jammy-server-cloudimg-amd64.img >/dev/null 2>>"$LOG_FILE"
else
    echo "Cloud image already exists, skipping download"
fi

# Install qemu-guest-agent in the image
echo "Installing qemu-guest-agent in the image..."
virt-customize -a jammy-server-cloudimg-amd64.img --install qemu-guest-agent

# Convert image to Proxmox format
echo "Converting image to QCOW2 format..."
qemu-img convert -O qcow2 jammy-server-cloudimg-amd64.img "vm-${VM_ID}-disk-0.qcow2" >/dev/null 2>&1

# Verify image conversion
if [ ! -f "vm-${VM_ID}-disk-0.qcow2" ]; then
    echo "Error: Image conversion failed"
    exit 1
fi

echo "Image handling completed successfully"

# Create base VM
echo "Creating base VM..."
qm create ${VM_ID} --name ${TEMPLATE_NAME} --memory ${MEMORY} --cores ${CORES} --net0 virtio,bridge=vmbr0

# Import disk to storage
echo "Importing disk to storage..."
qm importdisk ${VM_ID} "vm-${VM_ID}-disk-0.qcow2" ${STORAGE} 2>&1 | grep -v "transferred" || true

# Configure storage settings
echo "Configuring storage settings..."
qm set ${VM_ID} --scsihw virtio-scsi-pci --scsi0 ${STORAGE}:${VM_ID}/vm-${VM_ID}-disk-0.raw
qm resize ${VM_ID} scsi0 ${DISK_SIZE}

# Enable QEMU Guest Agent
echo "Enabling QEMU Guest Agent..."
qm set ${VM_ID} --agent enabled=1

# Verify VM creation
if ! qm status ${VM_ID} &>/dev/null; then
    echo "Error: VM creation failed"
    exit 1
fi

echo "VM creation and configuration completed successfully"

# Configure cloud-init drive
echo "Configuring cloud-init..."
qm set ${VM_ID} --ide2 ${STORAGE}:cloudinit
qm set ${VM_ID} --ciuser ubuntu --citype nocloud
qm set ${VM_ID} --ipconfig0 "ip=dhcp"

# Convert to template
echo "Converting VM to template..."
qm template ${VM_ID}

# Validation Steps
echo "Performing validation checks..."

# Verify template conversion
if ! qm config ${VM_ID} | grep -q 'template: 1'; then
    echo "Error: Template conversion failed"
    exit 1
fi

# Verify disk placement
if ! qm config ${VM_ID} | grep -q "^scsi0: ${STORAGE}:${VM_ID}/base-${VM_ID}-disk-0.raw"; then
    echo "Error: Disk not properly placed on ${STORAGE}"
    exit 1
fi

# Verify network configuration
if ! qm config ${VM_ID} | grep -q 'ipconfig0: ip=dhcp'; then
    echo "Error: DHCP network configuration not set correctly"
    exit 1
fi

# Verify QEMU Guest Agent is enabled
if ! qm config ${VM_ID} | grep -q 'agent: enabled=1'; then
    echo "Error: QEMU Guest Agent not enabled"
    exit 1
fi

echo "Template creation completed successfully!"
echo "Template ID: ${VM_ID}"
echo "Template Name: ${TEMPLATE_NAME}"
echo "Log file: ${LOG_FILE}"

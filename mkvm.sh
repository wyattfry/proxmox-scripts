#!/bin/bash
set -exuo pipefail

# Function to find the next available VM ID above 100
find_next_vm_id() {
    ID=100
    while qm status $ID &>/dev/null; do
        ((ID++))
    done
    echo $ID
}

# Default values
VM_ID=$(find_next_vm_id)
HOSTNAME=""
RAM_SIZE=2048
CPU_CORES=2
DISK_SIZE=20
STORAGE="nfs-storage"
SSH_KEY_FILE="/root/.ssh/authorized_keys"

# Function to show usage
show_usage() {
    echo "Usage: $0 [-h <hostname>] [-m <RAM_MB>] [-c <CPU_CORES>] [-d <DISK_GB>] [-s <storage>]"
    echo "  -h <hostname>    : Set hostname for the VM"
    echo "  -m <RAM_MB>      : Set RAM size in MB (default: 2048MB)"
    echo "  -c <CPU_CORES>   : Set number of CPU cores (default: 2)"
    echo "  -d <DISK_GB>     : Set disk size in GB (default: 20GB)"
    echo "  -s <storage>     : Set Proxmox storage (default: nfs-storage)"
    echo "  -t <template_id> : ID of template to clone"
    exit 1
}

# Parse command-line arguments
while getopts "h:m:c:d:s:t:" opt; do
    case "${opt}" in
        h) HOSTNAME=${OPTARG} ;;
        m) RAM_SIZE=${OPTARG} ;;
        c) CPU_CORES=${OPTARG} ;;
        d) DISK_SIZE=${OPTARG} ;;
        s) STORAGE=${OPTARG} ;;
        t) TEMPLATE_ID=${OPTARG} ;;
        *) show_usage ;;
    esac
done

# Ensure required arguments are provided
if [[ -z "$HOSTNAME" ]]; then
    echo "Error: Hostname is required!"
    show_usage
fi

TEMPLATE_ID=$(qm list | grep ubuntu-template | awk '{print $1}' | tail -1)
if [ -z "$TEMPLATE_ID" ]; then
    echo "Error: Ubuntu template not found!"
    exit 1
fi

echo "Using VM ID: $VM_ID"
echo "Using template ID: $TEMPLATE_ID"
echo "Using storage: $STORAGE"

# Clone the template
qm clone "$TEMPLATE_ID" "$VM_ID" --name "$HOSTNAME" --full true

# Configure VM settings
qm set "$VM_ID" --memory "$RAM_SIZE" --cores "$CPU_CORES" --ipconfig0 ip=dhcp
qm set "$VM_ID" --sshkeys "$SSH_KEY_FILE"

# Resize disk properly for NFS storage ############# OLD
# qm set "$VM_ID" --scsihw virtio-scsi-pci --scsi0 "$STORAGE:$DISK_SIZE"

############### NEW

# Identify the disk that was cloned
DISK_PATH=$(qm config "$VM_ID" | grep "scsi0" | awk -F ':' '{print $2}' | awk -F ',' '{print $1}')
if [[ -z "$DISK_PATH" ]]; then
    echo "Error: Failed to detect the disk for VM $VM_ID"
    exit 1
fi

# Resize the disk to the specified size
qm resize "$VM_ID" scsi0 "$DISK_SIZE"

################ END NEW

# Set hostname
qm set "$VM_ID" --ciuser wyatt
qm set "$VM_ID" --searchdomain local --nameserver 1.1.1.1

# Ensure correct path for Cloud-Init user-data file
CLOUD_INIT_FILE="/var/lib/qemu-server/$VM_ID.cloud-init"

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
  - hostnamectl set-hostname $HOSTNAME --pretty
  - apt-get update && apt-get install -y qemu-guest-agent libguestfs-tools avahi-daemon
  - systemctl enable --now qemu-guest-agent avahi-daemon
EOF

# Start the VM
qm start "$VM_ID"

echo "VM $HOSTNAME (ID: $VM_ID) created successfully!"

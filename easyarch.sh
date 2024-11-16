#!/bin/bash

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "You must run this script as root!"
    exit 1
fi

# ===== CONFIGURABLE VARIABLES =====
DISK="/dev/sda"                # Target disk for installation
BOOT_SIZE="1GiB"               # Size of the /boot partition
ROOT_SIZE="100GiB"             # Size of the root partition
USERNAME="ioan"                # Default username
USER_PASSWORD="rockstar"       # Password for the user
ROOT_PASSWORD="rockstar"       # Password for root
HOSTNAME="archlinux"           # Hostname for the system
TIMEZONE="Europe/Rome"         # Timezone
LOCALE_LANG="en_GB.UTF-8"      # System language
LOCALE_GEN="en_GB.UTF-8 it_IT.UTF-8" # Locale to generate
KEYBOARD_LAYOUT="it"           # Keyboard layout

# ===== SCRIPT START =====

# Preparation
echo "Preparation: Ensure you are connected to the Internet."
read -p "Press Enter to continue..."

# Set keyboard layout
echo "Setting keyboard layout to $KEYBOARD_LAYOUT..."
loadkeys "$KEYBOARD_LAYOUT"

# Synchronize system clock
echo "Synchronizing system clock..."
timedatectl set-ntp true

# Partitioning the disk
echo "Partitioning the disk $DISK..."
parted "$DISK" --script mklabel gpt
parted "$DISK" --script mkpart primary fat32 1MiB "$BOOT_SIZE"
parted "$DISK" --script set 1 esp on
parted "$DISK" --script mkpart primary ext4 "$BOOT_SIZE" "$ROOT_SIZE"
parted "$DISK" --script mkpart primary ext4 "$ROOT_SIZE" 100%

# Formatting partitions
echo "Formatting partitions..."
mkfs.fat -F32 "${DISK}1"
mkfs.ext4 "${DISK}2"
mkfs.ext4 "${DISK}3"

# Mounting partitions
echo "Mounting partitions..."
mount "${DISK}2" /mnt
mkdir /mnt/boot
mount "${DISK}1" /mnt/boot
mkdir /mnt/home
mount "${DISK}3" /mnt/home

# Installing the base system
echo "Installing the base system..."
pacstrap /mnt base linux linux-firmware linux-lts linux-lts-headers linux-headers base-devel

# Generating fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
echo "Entering the new system..."
arch-chroot /mnt /bin/bash <<EOF

# Setting timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Configuring localization
echo "$LOCALE_GEN" | tr ' ' '
' | sed -i 's/^/#/g' /etc/locale.gen
locale-gen
echo "LANG=$LOCALE_LANG" > /etc/locale.conf
echo "KEYMAP=$KEYBOARD_LAYOUT" > /etc/vconsole.conf

# Configuring hostname
echo "$HOSTNAME" > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Setting root password
echo "Setting root password..."
echo "root:$ROOT_PASSWORD" | chpasswd

# Creating user $USERNAME
echo "Creating user $USERNAME..."
useradd -m -G wheel $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Installing GRUB
echo "Installing GRUB..."
pacman -S --noconfirm grub efibootmgr os-prober dosfstools mtools
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Installing additional packages
echo "Installing additional packages..."
pacman -S --noconfirm networkmanager sddm plasma-meta konsole kwrite dolphin ark plasma-workspace egl-wayland partitionmanager kio-admin git nano firefox

# Enabling services
systemctl enable NetworkManager
systemctl enable sddm

EOF

# Exit chroot and unmount
echo "Exiting chroot and unmounting partitions..."
umount -R /mnt

# Finish installation
echo "Installation complete! Rebooting..."
reboot

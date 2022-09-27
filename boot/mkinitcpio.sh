#!/bin/bash
here=$(dirname $BASH_SOURCE)

cmdline=$(mktemp)
#echo "i915.fastboot=1 quiet consoleblank=60 acpi_backlight=vendor" > $cmdline
echo "quiet consoleblank=60 acpi_backlight=vendor" > $cmdline
mkinitcpio --config $here/mkinitcpio-systemd.conf --splash /boot/splash-arch.bmp --cmdline $cmdline --uefi /boot/EFI/Linux/arch-systemd.efi --microcode /boot/intel-ucode.img
rm $cmdline

install -C /usr/share/systemd/bootctl/splash-arch.bmp /boot/
install -C $here/loader/loader.conf /boot/loader/
install -C $here/loader/entries/*.conf /boot/loader/entries/


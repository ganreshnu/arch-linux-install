#!/bin/bash

# bootstrap the install with the base packages
useradd -m -G wheel,uucp john
passwd john

pacman -S vim efibootmgr brightnessctl libva-intel-driver pipewire-alsa pipewire-jack pipewire-pulse pipewire-docs noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra sway swaybg swayidle swaylock bemenu-wayland


#pacman -S sway swaybg swayidle swaylock bemenu-wayland alacritty firefox

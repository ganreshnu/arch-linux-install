#!/bin/bash

# bootstrap the install with the base packages
pacman -S brightnessctl
pacman -S pipewire-alsa pipewire-jack pipewire-pulse pipewire-docs wireplumber-docs
pacman -S wayland libva libva-intel-driver libva-utils vulkan-intel
pacman -S noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra
pacman -S sway swaybg swayidle swaylock bemenu-wayland foot
pacman -S mako jq
pacman -S flatpak xdg-desktop-portal-wl xdg-desktop-portal-gtk

#pacman -S alacritty firefox

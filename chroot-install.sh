#!/bin/bash

# bootstrap the install with the base packages
pacman -S brightnessctl
pacman -S pipewire-alsa pipewire-jack pipewire-pulse pipewire-docs wireplumber-docs
pacman -S wayland libva libva-intel-driver libva-utils vulkan-intel vulkan-mesa-layers

pacman -S noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra

pacman -S sway swaybg swayidle swaylock bemenu-wayland foot
pacman -S gcr #for pinentry-gnome3
pacman -S mako jq
pacman -S flatpak xdg-desktop-portal-wlr xdg-desktop-portal-gtk

#pacman -S alacritty firefox

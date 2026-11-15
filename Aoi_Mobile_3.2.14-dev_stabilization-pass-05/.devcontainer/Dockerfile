FROM mcr.microsoft.com/devcontainers/python:1-3.12-bookworm

USER root
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       ca-certificates curl unzip xvfb xauth sudo \
       libgl1 libgl1-mesa-dri libegl1 libvulkan1 mesa-vulkan-drivers \
       libx11-6 libxcursor1 libxinerama1 libxi6 libxrandr2 libxrender1 \
       libxkbcommon0 libwayland-client0 libwayland-cursor0 libwayland-egl1 \
       libasound2 libpulse0 libfontconfig1 libfreetype6 libudev1 libdbus-1-3 \
    && rm -rf /var/lib/apt/lists/*
# Keep the public bridge credential and Codespaces account files out of the
# process environment of untrusted project code. The bridge runs as vscode;
# Godot and shell commands run as this separate, non-login workspace account.
RUN groupadd --system aoi-workspace \
    && useradd --system --create-home --home-dir /home/aoi-runner \
       --shell /usr/sbin/nologin --gid aoi-workspace aoi-runner \
    && usermod -aG aoi-workspace vscode
USER vscode

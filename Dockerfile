# syntax=docker/dockerfile:1
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:0
ENV HOME=/home/desktop
ENV LIBGL_ALWAYS_SOFTWARE=1

# Minimal desktop, browser-based VNC, and Java for PokeMMO.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    openjdk-21-jre \
    xvfb \
    x11vnc \
    xfce4 \
    xfce4-terminal \
    dbus-x11 \
    adwaita-icon-theme \
    xterm \
    novnc \
    websockify \
    x11-utils \
    libgl1-mesa-dri \
    libgl1 \
    libasound2t64 \
    fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash desktop

COPY <<'EOF' /usr/local/bin/start-desktop
#!/bin/bash
set -euo pipefail

: "${VNC_PASSWORD:?Set VNC_PASSWORD in Fly Secrets before starting}"

mkdir -p "$HOME/.vnc"
x11vnc -storepasswd "$VNC_PASSWORD" "$HOME/.vnc/passwd"
chmod 600 "$HOME/.vnc/passwd"

Xvfb :0 -screen 0 1280x720x24 -nolisten tcp &
x_pid=$!

ready=0
for attempt in $(seq 1 50); do
    if xdpyinfo -display :0 >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 0.2
done

if [ "$ready" -ne 1 ]; then
    echo "Virtual display failed to start"
    exit 1
fi

dbus-run-session -- xfce4-session &
desktop_pid=$!

x11vnc -display :0 \
    -rfbauth "$HOME/.vnc/passwd" \
    -rfbport 5900 \
    -localhost \
    -forever \
    -shared &
vnc_pid=$!

websockify --web=/usr/share/novnc \
    0.0.0.0:6080 localhost:5900 &
web_pid=$!

trap 'kill "$x_pid" "$desktop_pid" "$vnc_pid" "$web_pid" 2>/dev/null || true' EXIT
wait -n "$x_pid" "$desktop_pid" "$vnc_pid" "$web_pid"
EOF

RUN chmod +x /usr/local/bin/start-desktop

RUN curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
      https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
    && curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources \
      https://brave-browser-apt-release.s3.brave.com/brave-browser.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends brave-browser \
    && rm -rf /var/lib/apt/lists/*
    
USER desktop
WORKDIR /home/desktop

EXPOSE 6080

CMD ["/usr/local/bin/start-desktop"]

FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture i386 && apt-get update && \
    apt-get install -y wine wine32 wine64 xvfb x11vnc x11-xserver-utils wmctrl openbox \
    novnc websockify xrdp wget nginx curl unzip dante-server gnupg2 && \
    rm -rf /var/lib/apt/lists/*

# Install Tailscale
RUN curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null && \
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list && \
    apt-get update && apt-get install -y tailscale && \
    rm -rf /var/lib/apt/lists/*

RUN curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh | bash

# Download MT5
RUN wget -q -O /root/mt5setup.exe \
"https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"

# Pre-install Wine Gecko and MT5
RUN Xvfb :99 -screen 0 1024x768x24 & \
    sleep 3 && \
    DISPLAY=:99 WINEDLLOVERRIDES="mscoree,mshtml=" wine /root/mt5setup.exe /auto; \
    sleep 90; \
    echo "MT5 step done"

COPY start.sh /start.sh
COPY resize_server.py /usr/share/novnc/resize_server.py
RUN sed -i "s/rfb.resizeSession = WebUtil.getConfigVar('resize', false)/rfb.resizeSession = true/" /usr/share/novnc/vnc_auto.html
RUN chmod +x /start.sh
RUN sed -i "s/rfb.scaleViewport = false/rfb.scaleViewport = true/" /usr/share/novnc/vnc_auto.html || true
CMD ["/start.sh"]

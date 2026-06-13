#!/bin/bash

# Start Tailscale
mkdir -p /var/lib/tailscale
tailscaled --state=/var/lib/tailscale/tailscaled.state &
sleep 3
tailscale up --authkey=${TAILSCALE_AUTHKEY} --hostname=zenserver

# Start display
Xvfb :1 -screen 0 1280x800x24 &
sleep 5
export DISPLAY=:1
openbox &
sleep 3

# Setup user
adduser --disabled-password --gecos "" rdpuser 2>/dev/null || true
echo "rdpuser:zenpass123" | chpasswd
usermod -aG sudo rdpuser

# Fix xrdp
sed -i 's/AllowRootLogin=false/AllowRootLogin=true/' /etc/xrdp/sesman.ini 2>/dev/null || true
sed -i 's/allowed_users=console/allowed_users=anybody/' /etc/X11/Xwrapper.config 2>/dev/null || true

cat > /etc/xrdp/startwm.sh << 'WEOF'
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
if [ -z "$DISPLAY" ]; then
    export DISPLAY=:10
fi
exec /usr/bin/openbox-session
WEOF
chmod +x /etc/xrdp/startwm.sh

# Setup rdpuser wine and mt5 script
cp -r /root/.wine /home/rdpuser/.wine 2>/dev/null || true
chown -R rdpuser:rdpuser /home/rdpuser/.wine 2>/dev/null || true

cat > /home/rdpuser/mt5.sh << 'MEOF'
#!/bin/bash
export DISPLAY=:10
export WINEPREFIX=/home/rdpuser/.wine
wine "/home/rdpuser/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"
MEOF
chmod +x /home/rdpuser/mt5.sh
chown rdpuser:rdpuser /home/rdpuser/mt5.sh

echo 'exec openbox-session' > /home/rdpuser/.xsession
chown rdpuser:rdpuser /home/rdpuser/.xsession
chmod +x /home/rdpuser/.xsession

# Start xrdp
rm -f /var/run/xrdp/xrdp.pid /var/run/xrdp/xrdp-sesman.pid
sleep 2
xrdp-sesman &
sleep 3
xrdp &
sleep 5

# Start noVNC
x11vnc -display :1 -nopw -listen 0.0.0.0 -rfbport 5900 -forever -bg -ncache 10
websockify --web=/usr/share/novnc 6080 localhost:5900 &

nohup python3 /usr/share/novnc/resize_server.py > /tmp/resize.log 2>&1 &
v2ray run -config /etc/v2ray/config.json > /tmp/v2ray.log 2>&1 &
wait

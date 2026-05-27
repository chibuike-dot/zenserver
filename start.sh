#!/bin/bash

# Start v2ray
v2ray run -c /usr/local/etc/v2ray/config.json &
sleep 2

# Nginx config
cat > /etc/nginx/sites-enabled/default << 'EOF'
server {
    listen 8080;
    location /v2ray {
        proxy_pass http://127.0.0.1:9090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
    location / {
        proxy_pass http://127.0.0.1:6080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
nginx

# Start display
Xvfb :1 -screen 0 1024x530x24 &
sleep 3
x11vnc -display :1 -nopw -listen 0.0.0.0 -rfbport 5900 -forever -bg -ncache 10
websockify --web=/usr/share/novnc 6080 localhost:5900 &
sleep 2

# Start MT5
MT5="/root/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"
if [ ! -f "$MT5" ]; then
    DISPLAY=:1 wine /root/mt5setup.exe /auto &
else
    DISPLAY=:1 wine "$MT5" &
    sleep 8
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz &
fi

nohup python3 /usr/share/novnc/resize_server.py > /tmp/resize.log 2>&1 &
wait

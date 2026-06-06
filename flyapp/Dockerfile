FROM ubuntu:22.04
RUN apt-get update && apt-get install -y \
    wget curl python3 xvfb x11vnc \
    && rm -rf /var/lib/apt/lists/*
CMD tail -f /dev/null

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/sshd && \
    useradd -m -s /bin/bash zenuser && \
    mkdir -p /home/zenuser/.ssh && \
    chmod 700 /home/zenuser/.ssh

COPY authorized_keys /home/zenuser/.ssh/authorized_keys

RUN chmod 600 /home/zenuser/.ssh/authorized_keys && \
    chown -R zenuser:zenuser /home/zenuser/.ssh

RUN echo "PermitRootLogin no" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication no" >> /etc/ssh/sshd_config && \
    echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config && \
    echo "AllowTcpForwarding yes" >> /etc/ssh/sshd_config && \
    echo "GatewayPorts yes" >> /etc/ssh/sshd_config

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D", "-e"]

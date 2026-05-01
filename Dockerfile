FROM ubuntu:24.04

RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus && \
    rm -rf /var/lib/apt/lists/* && \
    for unit in \
      apt-daily.service \
      apt-daily.timer \
      apt-daily-upgrade.service \
      apt-daily-upgrade.timer \
      systemd-networkd-wait-online.service; \
    do ln -sf /dev/null /etc/systemd/system/$unit; done

STOPSIGNAL SIGRTMIN+3
CMD ["/lib/systemd/systemd"]

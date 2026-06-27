FROM linuxserver/webtop:debian-xfce

# Prerequisitos del sistema + navegador para Playwright/control web
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl git xz-utils ca-certificates \
        build-essential g++ \
        ffmpeg ripgrep \
        chromium && \
    rm -rf /var/lib/apt/lists/*

# NO instalamos Hermes en build: /config es un bind mount que en runtime
# tapa cualquier cosa instalada aquí. La instalación ocurre en el primer
# arranque (autostart-hermes.sh) dentro de /config ya montado y escribible.

# Autostart: lanza una terminal con el setup si Hermes no está configurado
COPY autostart-hermes.sh /usr/local/bin/autostart-hermes.sh
RUN chmod +x /usr/local/bin/autostart-hermes.sh && \
    mkdir -p /etc/xdg/autostart && \
    printf '%s\n' \
        '[Desktop Entry]' \
        'Type=Application' \
        'Name=Hermes Setup' \
        'Exec=/usr/local/bin/autostart-hermes.sh' \
        'X-GNOME-Autostart-enabled=true' \
        > /etc/xdg/autostart/hermes-setup.desktop

# Oneshot s6 de provisioning desatendido: instala Hermes y aplica modelo +
# secretos desde las env vars del compose en el 1er boot (idempotente vía
# .setup-done). Patrón linuxserver: type=oneshot, up apunta al run script.
COPY hermes-provision.sh /etc/s6-overlay/s6-rc.d/init-hermes-provision/run
RUN chmod +x /etc/s6-overlay/s6-rc.d/init-hermes-provision/run && \
    printf 'oneshot' > /etc/s6-overlay/s6-rc.d/init-hermes-provision/type && \
    printf '/etc/s6-overlay/s6-rc.d/init-hermes-provision/run' \
        > /etc/s6-overlay/s6-rc.d/init-hermes-provision/up && \
    mkdir -p /etc/s6-overlay/s6-rc.d/init-hermes-provision/dependencies.d && \
    touch /etc/s6-overlay/s6-rc.d/init-hermes-provision/dependencies.d/init-services && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/init-hermes-provision

# Servicio s6-overlay (longrun) para el Hermes gateway. Lo supervisa el mismo
# s6 que el desktop → auto-restart, arranca en boot, independiente de terminal.
# Depende del provisioning para arrancar con la config ya aplicada.
COPY hermes-gateway-run /etc/s6-overlay/s6-rc.d/svc-hermes-gateway/run
RUN chmod +x /etc/s6-overlay/s6-rc.d/svc-hermes-gateway/run && \
    printf 'longrun' > /etc/s6-overlay/s6-rc.d/svc-hermes-gateway/type && \
    mkdir -p /etc/s6-overlay/s6-rc.d/svc-hermes-gateway/dependencies.d && \
    touch /etc/s6-overlay/s6-rc.d/svc-hermes-gateway/dependencies.d/init-services && \
    touch /etc/s6-overlay/s6-rc.d/svc-hermes-gateway/dependencies.d/init-hermes-provision && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/svc-hermes-gateway

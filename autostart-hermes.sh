#!/usr/bin/env bash
# Se ejecuta al iniciar la sesión XFCE (como el usuario abc).
# El setup ahora es DESATENDIDO: lo hace el oneshot s6 init-hermes-provision
# en el boot (instala Hermes + aplica config/secretos desde env vars y crea la
# sentinela .setup-done). Este autostart NO instala ni configura (evita carrera
# con el provisioner) — solo abre una terminal de diagnóstico si, tras esperar,
# el provisioning no completó (p.ej. sin red o secretos faltantes).

export HOME=/config

# Caso normal: ya provisionado → no molestar.
if [ -f "$HOME/.hermes/.setup-done" ]; then
    exit 0
fi

# Dar tiempo al provisioner (instalación de Hermes puede tardar varios minutos).
for _ in $(seq 1 60); do
    [ -f "$HOME/.hermes/.setup-done" ] && exit 0
    sleep 5
done

# Sigue sin provisionar: abrir terminal de diagnóstico (sin auto-instalar).
xfce4-terminal --title="Hermes — provisioning no completó" --hold -e "bash -lc '\
    export HOME=/config; \
    echo \"El provisioning desatendido no terminó. Causas típicas: sin red, o\"; \
    echo \"faltan secretos (TELEGRAM_BOT_TOKEN / LM_API_KEY) en el .env del compose.\"; \
    echo; \
    echo \"Log del provisioner:\"; \
    docker_logs=/config/.hermes/logs; \
    echo \"  (ver salida del boot con: docker logs <container> | grep provision)\"; \
    echo; \
    echo \"Para configurar a mano: hermes setup  &&  hermes gateway setup\"; \
    echo \"Binario: /config/.hermes/hermes-agent/venv/bin/hermes\"; \
    exec bash'"

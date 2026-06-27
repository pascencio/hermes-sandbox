#!/usr/bin/with-contenv bash
# Provisioning desatendido de Hermes. Lo corre el oneshot s6
# init-hermes-provision en cada boot (idempotente). Instala Hermes si falta y
# aplica modelo + secretos desde las env vars del compose, sin wizard.
set -u

export HOME=/config
HERMES=/config/.hermes/hermes-agent/venv/bin/hermes
ENVFILE=/config/.hermes/.env

run_as_abc() { s6-setuidgid abc env HOME=/config "$@"; }

# 1) Instalar Hermes si el binario no existe (primer boot)
if [ ! -x "$HERMES" ]; then
    echo "[provision] instalando Hermes (--skip-setup)..."
    run_as_abc bash -c 'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup' \
        || { echo "[provision] install falló (¿red?), reintenta próximo boot"; exit 0; }
fi

# 2) Aplicar config solo una vez (sentinela .setup-done)
if [ -f /config/.hermes/.setup-done ]; then
    echo "[provision] ya provisionado, nada que hacer"
    exit 0
fi

echo "[provision] aplicando config de modelo..."
run_as_abc "$HERMES" config set model.default        "${HERMES_MODEL:-google/gemma-4-e4b}"
run_as_abc "$HERMES" config set model.provider       "${HERMES_PROVIDER:-lmstudio}"
run_as_abc "$HERMES" config set model.base_url        "${LM_BASE_URL:-http://127.0.0.1:1234/v1}"
run_as_abc "$HERMES" config set model.context_length "${HERMES_CONTEXT_LENGTH:-65536}"

# 3) Escribir secretos/URLs en .env (idempotente: borra clave previa y re-agrega).
#    .env override config.yaml para base_url, así que LM_BASE_URL aquí manda.
echo "[provision] escribiendo .env..."
for kv in \
    "LM_BASE_URL=${LM_BASE_URL:-}" \
    "LM_API_KEY=${LM_API_KEY:-}" \
    "TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN:-}" \
    "TELEGRAM_ALLOWED_USERS=${TELEGRAM_ALLOWED_USERS:-}"; do
    key="${kv%%=*}"
    val="${kv#*=}"
    [ -z "$val" ] && continue   # no escribir claves vacías
    run_as_abc sed -i "/^[[:space:]]*#\?[[:space:]]*${key}=/d" "$ENVFILE" 2>/dev/null || true
    printf '%s\n' "$kv" | run_as_abc tee -a "$ENVFILE" >/dev/null
done

run_as_abc touch /config/.hermes/.setup-done
echo "[provision] listo — gateway arrancará a continuación"

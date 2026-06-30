#!/usr/bin/with-contenv bash
# Provisioning desatendido y GENÉRICO de Hermes. Lo corre el oneshot s6
# init-hermes-provision en cada boot (idempotente vía .setup-done).
#
# Filosofía: 100% agnóstico de provider. NO forzamos config ni provider.
# Instalamos Hermes, dejamos su config.yaml plantilla por defecto, y aplicamos
# SOLO los overrides que el usuario pase por env vars. Lo no especificado queda
# en el default de Hermes. Sirve igual para LM Studio/Ollama local (gratis, sin
# login Nous) o Claude/OpenAI/MiniMax (con tu API key). Ver .env.example.
#
# Convención de env vars (se pasan vía env_file .env del compose):
#   HERMES_CFG__<seccion>__<clave>=valor  ->  hermes config set <seccion>.<clave> valor
#       doble guion bajo "__" = punto; guion simple "_" se conserva.
#       ej: HERMES_CFG__model__context_length=65536  ->  model.context_length=65536
#   HERMES_ENV__<CLAVE>=valor             ->  escribe CLAVE=valor en /config/.hermes/.env
#       ej: HERMES_ENV__LM_API_KEY=xxx                ->  LM_API_KEY=xxx
#   HERMES_COMPUTER_USE=1                 ->  instala cua-driver (control del escritorio)
set -u

export HOME=/config
HERMES=/config/.hermes/hermes-agent/venv/bin/hermes
ENVFILE=/config/.hermes/.env

run_as_abc() { s6-setuidgid abc env HOME=/config "$@"; }

# 1) Instalar Hermes si el binario no existe (primer boot). Sin wizard.
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

# 3) Único default que imponemos: context_length (Hermes EXIGE ≥ 64K, no es
#    elección de provider). NO elegimos provider ni base_url por ti — eso es
#    100% agnóstico y se define en .env (HERMES_CFG__model__provider, etc.).
: "${HERMES_CFG__model__context_length:=65536}"
export HERMES_CFG__model__context_length

# 4) Overrides genéricos de config.yaml: cualquier env var HERMES_CFG__*
echo "[provision] aplicando overrides de config.yaml..."
while IFS= read -r var; do
    case "$var" in
        HERMES_CFG__*)
            key="${var#HERMES_CFG__}"   # model__context_length
            key="${key//__/.}"          # model.context_length
            val="${!var}"
            [ -z "$val" ] && continue
            echo "[provision]   config set ${key}"
            run_as_abc "$HERMES" config set "$key" "$val"
            ;;
    esac
done < <(compgen -e)

# 5) Secretos/URLs en .env: cualquier env var HERMES_ENV__* (idempotente:
#    borra la clave previa y re-agrega). .env override config.yaml para base_url.
echo "[provision] escribiendo .env..."
while IFS= read -r var; do
    case "$var" in
        HERMES_ENV__*)
            key="${var#HERMES_ENV__}"   # LM_API_KEY
            val="${!var}"
            [ -z "$val" ] && continue
            run_as_abc sed -i "/^[[:space:]]*#\?[[:space:]]*${key}=/d" "$ENVFILE" 2>/dev/null || true
            printf '%s\n' "${key}=${val}" | run_as_abc tee -a "$ENVFILE" >/dev/null
            ;;
    esac
done < <(compgen -e)

# 5b) Telegram home channel: Telegram puede responder mensajes entrantes sin
#     home channel, pero para un setup desatendido completo (cron, handoff,
#     notificaciones y envíos iniciados desde CLI) conviene dejarlo definido.
#     Si el usuario configuró exactamente un allowed user y omitió el home,
#     inferimos ese chat como home de forma segura.
if grep -qE '^[[:space:]]*TELEGRAM_BOT_TOKEN=.+' "$ENVFILE" 2>/dev/null \
   && ! grep -qE '^[[:space:]]*TELEGRAM_HOME_CHANNEL=.+' "$ENVFILE" 2>/dev/null; then
    telegram_allowed="$(
        grep -E '^[[:space:]]*TELEGRAM_ALLOWED_USERS=' "$ENVFILE" 2>/dev/null \
            | tail -n 1 \
            | cut -d= -f2- \
            | tr -d '[:space:]'
    )"
    if [ -n "$telegram_allowed" ] && [[ "$telegram_allowed" != *,* ]]; then
        echo "[provision] TELEGRAM_HOME_CHANNEL no definido; usando único TELEGRAM_ALLOWED_USERS"
        run_as_abc sed -i "/^[[:space:]]*#\?[[:space:]]*TELEGRAM_HOME_CHANNEL=/d" "$ENVFILE" 2>/dev/null || true
        printf '%s\n' "TELEGRAM_HOME_CHANNEL=${telegram_allowed}" | run_as_abc tee -a "$ENVFILE" >/dev/null
    elif [ -z "$telegram_allowed" ]; then
        echo "[provision] aviso: Telegram no tiene TELEGRAM_HOME_CHANNEL; envía /sethome desde el chat principal"
    else
        echo "[provision] aviso: Telegram tiene múltiples allowed users; define TELEGRAM_HOME_CHANNEL o envía /sethome"
    fi
fi

# 6) Computer use (opcional, gratuito): instala cua-driver (trycua/cua) vía MCP.
#    Telemetría off. No bloquea el provisioning si falla (reintenta próximo boot).
if [ "${HERMES_COMPUTER_USE:-0}" = "1" ]; then
    echo "[provision] instalando cua-driver (computer use)..."
    run_as_abc env CUA_DRIVER_RS_TELEMETRY_ENABLED=0 \
        "$HERMES" computer-use install \
        || echo "[provision] computer-use install falló (no bloquea), reintenta próximo boot"
fi

run_as_abc touch /config/.hermes/.setup-done
echo "[provision] listo — gateway arrancará a continuación"

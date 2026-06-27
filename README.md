# hermes-sandbox

Entorno Docker reproducible para correr el **[Hermes Agent](https://hermes-agent.nousresearch.com/)** (Nous Research) dentro de un escritorio XFCE accesible por navegador, basado en [`linuxserver/webtop`](https://docs.linuxserver.io/images/docker-webtop/).

El setup completo (instalación de Hermes, modelo, credenciales y arranque del gateway de mensajería) es **desatendido**: en el primer boot el contenedor se autoconfigura desde variables de entorno, sin asistentes interactivos.

## Arquitectura

| Componente | Rol |
|---|---|
| `linuxserver/webtop:debian-xfce` | Imagen base: escritorio XFCE servido por web (s6-overlay v3 como PID 1) |
| `init-hermes-provision` (oneshot s6) | Primer boot: instala Hermes y aplica modelo + secretos desde env vars. Idempotente vía sentinela `.setup-done` |
| `svc-hermes-gateway` (longrun s6) | Corre el gateway de mensajería en foreground, supervisado por s6 (auto-restart, arranca en boot). Depende del oneshot |
| `autostart-hermes.sh` | Solo diagnóstico: abre una terminal si el provisioning no completó |

Hermes vive en `/config/.hermes/` y persiste vía el bind mount `./config:/config`.

## Prerrequisitos

- Docker + Docker Compose
- Un servidor de inferencia accesible desde el contenedor (este sandbox asume [LM Studio](https://lmstudio.ai/) en la red local, p. ej. `http://192.168.1.18:1234/v1`). El modelo debe servir **≥ 64K de contexto** (mínimo que exige Hermes).
- Un bot de Telegram ([@BotFather](https://t.me/BotFather)) si usas el gateway de Telegram.

## Configuración

Toda la configuración vive en `.env` (no se versiona — `.gitignore` cubre `.env*`):

```dotenv
# Webtop
TZ=America/Santiago
TITLE=Hermes Agent
CUSTOM_USER=tu_usuario
PASSWORD=tu_password

# Provisioning desatendido de Hermes
HERMES_MODEL=google/gemma-4-e4b
HERMES_PROVIDER=lmstudio
HERMES_CONTEXT_LENGTH=65536
LM_BASE_URL=http://192.168.1.18:1234/v1      # DEBE incluir /v1
LM_API_KEY=lm-studio                          # LM Studio acepta cualquier valor
TELEGRAM_BOT_TOKEN=123456:ABC...              # de @BotFather
TELEGRAM_ALLOWED_USERS=                       # IDs separados por coma (opcional)
```

> **Importante:** `LM_BASE_URL` **sobreescribe** `model.base_url` de `config.yaml` y debe terminar en `/v1` (el endpoint de LM Studio es `/v1/chat/completions`).

## Uso

```bash
docker compose up -d --build
```

Abre el escritorio en `http://localhost:3300`. En el primer boot el provisioning instala Hermes y arranca el gateway automáticamente (puede tardar unos minutos descargando dependencias). Sigue el progreso con:

```bash
docker logs -f hermes-webtop | grep -i provision
```

### Reinstalación limpia

```bash
docker compose down
sudo rm -rf ./config          # contiene archivos de root creados por el contenedor
docker compose up -d --build
```

Vuelve a quedar 100% configurado sin intervención. Los permisos del bind mount se autocorrigen en cada boot (`init-adduser` de linuxserver corre `lsiown abc:abc /config`).

### Reprovisionar tras cambiar valores

```bash
# edita .env, luego:
docker exec hermes-webtop rm -f /config/.hermes/.setup-done
docker compose up -d           # recrea el contenedor → el oneshot reaplica
```

## Gestión del gateway

```bash
s6-svc -d /run/service/svc-hermes-gateway   # detener
s6-svc -u /run/service/svc-hermes-gateway   # iniciar
s6-svc -r /run/service/svc-hermes-gateway   # reiniciar (tras editar config/.env)
docker logs hermes-webtop                   # ver logs
```

El binario de Hermes (no está en el `PATH` por defecto): `/config/.hermes/hermes-agent/venv/bin/hermes`.

## Notas de diseño (gotchas)

- **No se instala Hermes en build.** `/config` es un bind mount que en runtime tapa cualquier cosa escrita durante el build; la instalación ocurre en el primer boot dentro de `/config` ya montado.
- **`config.yaml` no implica configurado.** El instalador deja un `config.yaml` plantilla; el estado real se marca con la sentinela `.setup-done`.
- **`hermes gateway run` y s6.** Webtop usa s6-overlay, así que Hermes intenta redirigir el gateway a su propia supervisión s6 (que no existe aquí) y falla con `no such gateway 'default'`. Se evita con `HERMES_GATEWAY_NO_SUPERVISE=1` y corriendo el gateway como servicio s6 nativo de la imagen.

## Licencia

[Apache License 2.0](./LICENSE).

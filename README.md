# hermes-sandbox

Entorno Docker reproducible para correr el **[Hermes Agent](https://hermes-agent.nousresearch.com/)** (Nous Research) dentro de un escritorio XFCE accesible por navegador, basado en [`linuxserver/webtop`](https://docs.linuxserver.io/images/docker-webtop/).

El setup completo (instalación de Hermes, modelo, credenciales y arranque del gateway de mensajería) es **desatendido**: en el primer boot el contenedor se autoconfigura desde variables de entorno, sin asistentes interactivos.

No fuerza una configuración fija: instala Hermes, deja su `config.yaml` plantilla por defecto, y aplica **solo** los overrides que pases por env vars (convención genérica `HERMES_CFG__*` / `HERMES_ENV__*`). Es **agnóstico de provider** — sirve igual con un modelo local gratis (LM Studio, Ollama) o con un provider de pago (Claude, OpenAI, MiniMax). Nunca exige login con Nous.

## Arquitectura

| Componente | Rol |
|---|---|
| `linuxserver/webtop:debian-xfce` | Imagen base: escritorio XFCE servido por web (s6-overlay v3 como PID 1) |
| `init-hermes-provision` (oneshot s6) | Primer boot: instala Hermes y aplica config + credenciales (`HERMES_CFG__*` / `HERMES_ENV__*`) desde env vars. Idempotente vía sentinela `.setup-done` |
| `svc-hermes-gateway` (longrun s6) | Corre el gateway de mensajería en foreground, supervisado por s6 (auto-restart, arranca en boot). Depende del oneshot |
| `autostart-hermes.sh` | Solo diagnóstico: abre una terminal si el provisioning no completó |

Hermes vive en `/config/.hermes/` y persiste vía el bind mount `./config:/config`.

## Prerrequisitos

- Docker + Docker Compose
- Acceso a un provider de modelo (elige uno en `.env`): local gratis ([LM Studio](https://lmstudio.ai/), [Ollama](https://ollama.com/)) o de pago con tu API key (Claude, OpenAI, MiniMax). El modelo debe servir **≥ 64K de contexto** (mínimo que exige Hermes).
- Un bot de Telegram ([@BotFather](https://t.me/BotFather)) si usas el gateway de Telegram.

## Configuración

Toda la configuración vive en `.env` (no se versiona — `.gitignore` cubre `.env*`; hay un `.env.example` de referencia). El compose pasa **todo** `.env` al contenedor (`env_file`), así que agregas o quitas claves sin tocar `docker-compose.yaml`.

Dos convenciones genéricas, ambas opcionales — lo que no definas queda en el default de Hermes:

| Prefijo | Efecto | Regla de nombre |
|---|---|---|
| `HERMES_CFG__<sec>__<clave>` | `hermes config set <sec>.<clave> <valor>` (edita `config.yaml`) | `__` = `.` ; `_` simple se conserva |
| `HERMES_ENV__<CLAVE>` | escribe `CLAVE=<valor>` en el `.env` de Hermes (secretos/URLs) | tal cual |

`model.context_length` ilustra la regla de nombres: `HERMES_CFG__model__context_length` → `model.context_length` (el `__` es `.`, no `model.context.length`). Si lo omites, el provisioning lo fija en `65536` (Hermes exige ≥ 64K).

### Elegir provider

El sandbox es **agnóstico**: defines provider, modelo y credencial en `.env`. Para cualquier provider, `base_url` va por `HERMES_CFG__model__base_url` (clave genérica de `config.yaml`) — **no** uses los `*_BASE_URL` específicos (`LM_BASE_URL`, etc.): son redundantes y atan la config a un provider.

| Provider | `HERMES_CFG__model__provider` | API key | `base_url` default |
|---|---|---|---|
| LM Studio (local, gratis) | `lmstudio` | `HERMES_ENV__LM_API_KEY` (cualquier valor) | `http://127.0.0.1:1234/v1` |
| Ollama (local, gratis) | `ollama` | — (ninguna) | `http://127.0.0.1:11434/v1` |
| Claude / Anthropic | `anthropic` | `HERMES_ENV__ANTHROPIC_API_KEY` | `https://api.anthropic.com` |
| OpenAI | `openai-api` ⚠️ | `HERMES_ENV__OPENAI_API_KEY` | `https://api.openai.com/v1` |
| MiniMax | `minimax` | `HERMES_ENV__MINIMAX_API_KEY` | `https://api.minimax.io/anthropic` |

> ⚠️ **OpenAI:** `provider=openai` se rutea internamente a **OpenRouter**. Para usar OpenAI directo con tu key usa `provider=openai-api`.
>
> **Local:** desde el contenedor, `127.0.0.1` apunta al contenedor, no al host. Para LM Studio/Ollama corriendo en tu máquina usa la IP LAN (ej. `http://192.168.1.18:1234/v1`). El endpoint de LM Studio debe terminar en `/v1`.

Ejemplo mínimo (`.env`) con LM Studio local. Ver [`.env.example`](./.env.example) para los 5 providers:

```dotenv
# Webtop
TZ=America/Santiago
TITLE=Hermes Agent
CUSTOM_USER=tu_usuario
PASSWORD=tu_password

# Provider (config.yaml — "__" = ".")
HERMES_CFG__model__provider=lmstudio
HERMES_CFG__model__default=google/gemma-4-e4b
HERMES_CFG__model__base_url=http://127.0.0.1:1234/v1

# Credencial (.env de Hermes)
HERMES_ENV__LM_API_KEY=lm-studio                  # LM Studio acepta cualquier valor

# Gateway Telegram (opcional)
HERMES_ENV__TELEGRAM_BOT_TOKEN=123456:ABC...      # de @BotFather
HERMES_ENV__TELEGRAM_ALLOWED_USERS=               # IDs separados por coma
HERMES_ENV__TELEGRAM_HOME_CHANNEL=                # recomendado; si hay un solo allowed user, se infiere

# Computer use (cua-driver) — control del escritorio. 1=on, 0=off
HERMES_COMPUTER_USE=1
```

### Computer use (control del escritorio)

Con `HERMES_COMPUTER_USE=1`, el provisioning instala [`cua-driver`](https://github.com/trycua/cua) (open-source, gratuito, sin login Nous) que Hermes maneja por MCP. Controla el propio escritorio XFCE de webtop — que **sí** soporta computer use: usa X11 + AT-SPI + input XTest, todo dentro del contenedor, **sin permisos del host** (nada de `--privileged` ni `/dev/uinput`). Las dependencias (`at-spi2-core`, `libxtst6`, `dbus-x11`) ya van en la imagen.

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
docker compose up -d --force-recreate   # contenedor fresco → el oneshot reaplica config.yaml/.env
```

`--force-recreate` garantiza que el gateway arranque de nuevo y cargue la config recién aplicada. Si en cambio solo editaste valores en caliente (sin recrear), reinicia el gateway para que recargue: `docker exec hermes-webtop s6-svc -r /run/service/svc-hermes-gateway`.

## Gestión del gateway

```bash
s6-svc -d /run/service/svc-hermes-gateway   # detener
s6-svc -u /run/service/svc-hermes-gateway   # iniciar
s6-svc -r /run/service/svc-hermes-gateway   # reiniciar (tras editar config/.env)
docker logs hermes-webtop                   # ver logs
```

El binario de Hermes (no está en el `PATH` por defecto): `/config/.hermes/hermes-agent/venv/bin/hermes`.

### Telegram: home channel

El mensaje `Type /sethome to make this chat your home channel, or ignore to skip.`
no es un error: Hermes lo muestra cuando Telegram ya está conectado pero aún no
tiene un chat home configurado. El home channel no es necesario para responder
mensajes entrantes, pero sí para un flujo desatendido completo: cron, handoffs,
notificaciones de reinicio y envíos iniciados desde CLI.

Si `HERMES_ENV__TELEGRAM_ALLOWED_USERS` contiene un único ID y
`HERMES_ENV__TELEGRAM_HOME_CHANNEL` está vacío, el provisioning usa ese ID como
home automáticamente. Si tienes varios usuarios permitidos, define
`HERMES_ENV__TELEGRAM_HOME_CHANNEL=<chat_id>` o envía `/sethome` una vez desde el
chat privado o grupo que quieras usar como principal.

## Notas de diseño (gotchas)

- **No se instala Hermes en build.** `/config` es un bind mount que en runtime tapa cualquier cosa escrita durante el build; la instalación ocurre en el primer boot dentro de `/config` ya montado.
- **`config.yaml` no implica configurado.** El instalador deja un `config.yaml` plantilla; el estado real se marca con la sentinela `.setup-done`.
- **`hermes gateway run` y s6.** Webtop usa s6-overlay, así que Hermes intenta redirigir el gateway a su propia supervisión s6 (que no existe aquí) y falla con `no such gateway 'default'`. Se evita con `HERMES_GATEWAY_NO_SUPERVISE=1` y corriendo el gateway como servicio s6 nativo de la imagen.

## Licencia

[Apache License 2.0](./LICENSE).

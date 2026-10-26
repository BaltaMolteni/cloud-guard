#!/usr/bin/env bash
# Prepara una terminal para la demo en vivo, donde los comandos se escriben a mano.
#   source demo/terminal.sh admin      quien administra la cuenta (y responde al incidente)
#   source demo/terminal.sh atacante   alguien de afuera: sin credenciales propias
# Después, aws, git, gitleaks y prowler se usan igual que contra AWS real.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "Este archivo se carga con source en una ventana de Git Bash: source demo/terminal.sh admin|atacante"
  exit 1
fi
ROL_TERMINAL="${1:-admin}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || return 1
set +euo pipefail
MOSTRAR_COMANDOS=0
CUENTA="$(cat "$WORK/cuenta" 2>/dev/null)"
export BUCKET CUENTA

if [[ $- != *i* ]]; then
  mal "Esta shell no es interactiva (¿se corrió con ! desde Claude Code?): abrir una ventana de Git Bash y cargarlo ahí"
fi
if [ -z "$CUENTA" ]; then
  mal "Todavía no se preparó la demo: correr ./demo/setup.sh"
elif [ "$MODO" = floci ] && ! floci_responde; then
  mal "Floci no está corriendo: correr ./demo/setup.sh"
elif [ "$MODO" = floci ] && ! aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  # Floci guarda todo en memoria: si se reinició el contenedor o Docker, arranca vacío.
  mal "Floci se reinició y perdió el estado: correr ./demo/setup.sh"
fi

# Si gitleaks o prowler no están instalados, se usan sus imágenes de Docker con el mismo comando.
if ! type -P gitleaks >/dev/null; then
  gitleaks() {
    local args=("$@") repo=.
    # El último argumento, si es una carpeta, es el repositorio a revisar.
    if [ $# -gt 0 ] && [ -d "${args[-1]}" ]; then
      repo="${args[-1]}"
      unset 'args[-1]'
    fi
    gitleaks_en "$repo" "${args[@]}"
  }
fi
if ! type -P prowler >/dev/null; then
  prowler() {
    [ "$1" = aws ] && shift
    prowler_aws "$@"
  }
fi

case "$ROL_TERMINAL" in
  admin)
    PS1='\[\e[1;32m\]admin\[\e[0m\] \w \$ '
    printf '\033]0;admin\007'
    ;;
  atacante)
    # Sin perfiles ni credenciales: solo Internet (o Floci) y lo que encuentre.
    unset AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    export AWS_SHARED_CREDENTIALS_FILE="$RAIZ/$WORK/sin-credenciales" AWS_CONFIG_FILE="$RAIZ/$WORK/sin-credenciales"
    mkdir -p "$WORK/atacante-home"
    cd "$WORK/atacante-home" || return
    PS1='\[\e[1;31m\]atacante\[\e[0m\] \w \$ '
    printf '\033]0;atacante\007'
    ;;
  *)
    mal "Uso: source demo/terminal.sh admin|atacante"
    return 1
    ;;
esac

ok "Terminal de $ROL_TERMINAL lista (modo $MODO, bucket $BUCKET)"
if [ "$ROL_TERMINAL" = atacante ]; then
  info "Repositorio de la empresa: ../remoto/app-g10.git"
fi

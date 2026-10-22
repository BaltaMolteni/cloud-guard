#!/usr/bin/env bash
# Funciones comunes de la demo. Cada script la incluye con: source "$(dirname "$0")/lib.sh"
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"
source config.env

# Todo lo generado (claves, repos de la app y del atacante, descargas) vive acá y está en .gitignore.
WORK=.work
mkdir -p "$WORK"

export AWS_DEFAULT_REGION="$REGION" AWS_PAGER=""
ARCHIVO=clientes_ficticios.csv
FLOCI_CONTENEDOR=g10-floci

case "$MODO" in
  floci)
    FLOCI_URL="http://localhost:$FLOCI_PUERTO"
    # La CLI y boto3 mandan todas las llamadas al emulador. Las credenciales "test" son las del
    # administrador de la cuenta emulada (000000000000).
    export AWS_ENDPOINT_URL="$FLOCI_URL" AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test
    unset AWS_PROFILE AWS_SESSION_TOKEN
    URL_PUBLICA="$FLOCI_URL/$BUCKET/$ARCHIVO"
    ;;
  aws)
    if [ -n "$AWS_PROFILE_ADMIN" ]; then
      export AWS_PROFILE="$AWS_PROFILE_ADMIN"
    fi
    URL_PUBLICA="https://$BUCKET.s3.$REGION.amazonaws.com/$ARCHIVO"
    ;;
  *)
    printf 'MODO debe ser floci o aws (es "%s")\n' "$MODO"; exit 1 ;;
esac

titulo() { printf '\n\033[1;36m══════ %s ══════\033[0m\n' "$*"; }
paso()   { printf '\n\033[1;33m▶ %s\033[0m\n' "$*"; }
info()   { printf '  %s\n' "$*"; }
ok()     { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
mal()    { printf '\033[1;31m✘ %s\033[0m\n' "$*"; }
cmd()    { printf '\033[0;90m$ %s\033[0m\n' "$*" >&2; }
run() {
  local mostrar=() a
  for a in "$@"; do
    if [[ "$a" == *" "* ]]; then mostrar+=("\"$a\""); else mostrar+=("$a"); fi
  done
  cmd "${mostrar[*]}"
  "$@"
}

pausa() {
  if [ "$PAUSA" = 1 ]; then
    read -rp $'\n[Enter para continuar] ' _ || true
  fi
}

requiere() {
  for t in "$@"; do
    command -v "$t" >/dev/null || { mal "Falta '$t' en el PATH"; exit 1; }
  done
}

# aws con salida capturable: en Windows la CLI devuelve fin de línea \r\n.
awsq() { aws "$@" | tr -d '\r'; }

# Ruta que entienden los programas nativos de Windows (Docker); en Linux/macOS no cambia.
winpath() {
  if command -v cygpath >/dev/null; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

# Copia una política de politicas/ a .work/ con el bucket y la cuenta reales,
# y devuelve la ruta lista para --policy-document.
politica() {
  mkdir -p "$WORK/politicas"
  sed -e "s/g10-demo-datos/$BUCKET/g" -e "s/__CUENTA__/${CUENTA:-}/g" "politicas/$1" > "$WORK/politicas/$1"
  printf 'file://%s' "$WORK/politicas/$1"
}

cuenta_actual() { awsq sts get-caller-identity --query Account --output text; }

# Los actos modifican la cuenta (el acto 1 abre el acceso público a nivel de cuenta):
# solo corren sobre la cuenta que se confirmó en setup.sh.
verificar_cuenta() {
  [ -f "$WORK/cuenta" ] || { mal "Primero correr ./demo/setup.sh"; exit 1; }
  if [ "$MODO" = floci ] && ! floci_responde; then
    mal "Floci no está corriendo: volver a correr ./demo/setup.sh"; exit 1
  fi
  CUENTA="$(cat "$WORK/cuenta")"
  local actual
  actual="$(cuenta_actual)"
  if [ "$actual" != "$CUENTA" ]; then
    mal "Las credenciales apuntan a la cuenta $actual, pero la demo se preparó en $CUENTA"
    exit 1
  fi
}

floci_responde() { curl -s -o /dev/null "$FLOCI_URL"; }

# Arranca un Floci limpio, con las dos opciones que hacen que se comporte como AWS en la demo:
# evaluar políticas de IAM y evaluar políticas de bucket y accesos anónimos en S3.
floci_arrancar() {
  docker rm -f "$FLOCI_CONTENEDOR" >/dev/null 2>&1 || true
  run docker run -d --name "$FLOCI_CONTENEDOR" -p "$FLOCI_PUERTO:4566" \
    -e FLOCI_SERVICES_IAM_ENFORCEMENT_ENABLED=true \
    -e FLOCI_SERVICES_S3_ENFORCE_AUTH=true \
    "$FLOCI_IMAGE" >/dev/null
  for _ in $(seq 1 30); do
    floci_responde && return 0
    sleep 1
  done
  mal "Floci no respondió en $FLOCI_URL"; exit 1
}

# Bloqueo de acceso público a nivel de cuenta (on/off).
bloqueo_cuenta() {
  local conf=BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  if [ "$1" = on ]; then
    cmd "aws s3control put-public-access-block --account-id $CUENTA --public-access-block-configuration $conf"
  else
    cmd "aws s3control delete-public-access-block --account-id $CUENTA"
  fi
  if [ "$MODO" = aws ]; then
    if [ "$1" = on ]; then
      aws s3control put-public-access-block --account-id "$CUENTA" --public-access-block-configuration "$conf"
    else
      aws s3control delete-public-access-block --account-id "$CUENTA"
    fi
    return
  fi
  # La CLI arma el host de S3 Control como <cuenta>.localhost, que no resuelve en todos los sistemas:
  # contra Floci se manda la misma llamada a la API firmada con curl.
  local api=(curl -sf --aws-sigv4 "aws:amz:$REGION:s3" --user test:test
             -H "x-amz-account-id: $CUENTA" "$FLOCI_URL/v20180820/configuration/publicAccessBlock")
  if [ "$1" = on ]; then
    "${api[@]}" -X PUT --data "<PublicAccessBlockConfiguration xmlns=\"http://awss3control.amazonaws.com/doc/2018-08-20/\"><BlockPublicAcls>true</BlockPublicAcls><IgnorePublicAcls>true</IgnorePublicAcls><BlockPublicPolicy>true</BlockPublicPolicy><RestrictPublicBuckets>true</RestrictPublicBuckets></PublicAccessBlockConfiguration>"
  else
    "${api[@]}" -X DELETE
  fi
}

http_status() { curl -s -o /dev/null -w '%{http_code}' "$URL_PUBLICA"; }

# Pide el archivo sin credenciales hasta obtener el código esperado (los cambios de S3 tardan unos segundos).
esperar_http() {
  local esperado="$1" codigo
  cmd "curl -s -o /dev/null -w '%{http_code}' $URL_PUBLICA"
  for _ in $(seq 1 20); do
    codigo="$(http_status)"
    [ "$codigo" = "$esperado" ] && break
    sleep 2
  done
  info "HTTP $codigo"
}

gitleaks_en() {
  local repo="$1"; shift
  cmd "gitleaks $* ."
  if command -v gitleaks >/dev/null; then
    (cd "$repo" && gitleaks "$@" .)
  else
    MSYS_NO_PATHCONV=1 docker run --rm -v "$(winpath "$(cd "$repo" && pwd)"):/repo" \
      "$GITLEAKS_IMAGE" "$@" /repo
  fi
}

prowler_aws() {
  cmd "prowler aws $*"
  if command -v prowler >/dev/null; then
    prowler aws "$@" -o "$WORK/prowler"
  else
    # El contenedor no ve ~/.aws: se le pasan las credenciales del perfil actual por entorno.
    # Con Floci, "localhost" dentro del contenedor es el propio contenedor: se apunta al host.
    (
      eval "$(awsq configure export-credentials --format env)"
      endpoint=()
      if [ -n "${AWS_ENDPOINT_URL:-}" ]; then
        endpoint=(-e "AWS_ENDPOINT_URL=${AWS_ENDPOINT_URL/localhost/host.docker.internal}")
      fi
      MSYS_NO_PATHCONV=1 docker run --rm --add-host=host.docker.internal:host-gateway \
        -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_DEFAULT_REGION \
        "${endpoint[@]}" "$PROWLER_IMAGE" aws "$@"
    )
  fi
}

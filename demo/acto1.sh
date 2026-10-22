#!/usr/bin/env bash
# Acto 1 (eje 1, configuraciones erróneas): el bucket público.
# Romper, mostrar el daño, detectar con Prowler y corregir con el bloqueo de acceso público.
source "$(dirname "$0")/lib.sh"
verificar_cuenta

titulo "Acto 1: el bucket público"

paso "0. Punto de partida: el archivo existe, pero sin credenciales no se puede leer"
esperar_http 403
pausa

paso "1. Romper: se apaga el bloqueo de acceso público (cuenta y bucket) y se abre la política"
bloqueo_cuenta off
run aws s3api delete-public-access-block --bucket "$BUCKET"
POLITICA="$(politica lectura_publica.json)"
run cat "${POLITICA#file://}"
cmd "aws s3api put-bucket-policy --bucket $BUCKET --policy $POLITICA"
# Apagar el bloqueo tarda unos segundos en aplicarse; hasta entonces S3 rechaza la política pública.
aplicada=0
for _ in $(seq 1 15); do
  if aws s3api put-bucket-policy --bucket "$BUCKET" --policy "$POLITICA" 2>/dev/null; then aplicada=1; break; fi
  sleep 2
done
[ "$aplicada" = 1 ] || { mal "S3 sigue rechazando la política pública: reintentar en unos segundos"; exit 1; }
pausa

paso "2. Mostrar el daño: cualquiera lo descarga, sin iniciar sesión"
info "Abrir en una ventana de incógnito:"
info "  $URL_PUBLICA"
esperar_http 200
cmd "curl -s $URL_PUBLICA"
curl -s "$URL_PUBLICA" | head -6
pausa

paso "3. Detectar: Prowler revisa la postura de la cuenta"
prowler_aws --checks s3_bucket_public_access --region "$REGION" --verbose || true
pausa

paso "4. Corregir: se reactiva el bloqueo de acceso público"
run aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
# También a nivel de cuenta, para que ningún bucket nuevo pueda volver a abrirse.
bloqueo_cuenta on
esperar_http 403
info "La política con Principal \"*\" sigue escrita en el bucket: el bloqueo la anula igual."
info "Recargar la pestaña de incógnito: ahora responde 403 (Forbidden)."
ok "Fin del acto 1. Siguiente: ./demo/acto2.sh"

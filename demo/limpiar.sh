#!/usr/bin/env bash
# Borra todo lo que creó la demo y deja la cuenta con el bloqueo de acceso público activado.
source "$(dirname "$0")/lib.sh"

titulo "Limpieza"

if [ "$MODO" = floci ]; then
  # Todo el estado vive en el contenedor: alcanza con borrarlo.
  run docker rm -f "$FLOCI_CONTENEDOR" >/dev/null || true
  rm -rf "$WORK"
  ok "Floci detenido y archivos de la demo borrados"
  exit 0
fi

verificar_cuenta
info "Se borran el bucket $BUCKET, el usuario $USUARIO_APP, su clave y el rol $ROL_LECTURA."
read -rp "  ¿Continuar? (s/N) " resp
[ "$resp" = s ] || { mal "Cancelado"; exit 1; }

bloqueo_cuenta on
run aws s3 rb "s3://$BUCKET" --force || true

for clave in $(awsq iam list-access-keys --user-name "$USUARIO_APP" --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null); do
  run aws iam delete-access-key --user-name "$USUARIO_APP" --access-key-id "$clave"
done
run aws iam delete-user-policy --user-name "$USUARIO_APP" --policy-name s3-todo || true
run aws iam delete-user --user-name "$USUARIO_APP" || true

run aws iam delete-role-policy --role-name "$ROL_LECTURA" --policy-name solo-lectura || true
run aws iam delete-role --role-name "$ROL_LECTURA" || true

rm -rf "$WORK"
ok "Cuenta limpia"

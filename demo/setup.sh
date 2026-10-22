#!/usr/bin/env bash
# Prepara la cuenta de la demo: el bucket privado con datos ficticios, el usuario g10-app
# con permisos excesivos y su clave, y el rol de solo lectura que lo reemplaza en el acto 2.
source "$(dirname "$0")/lib.sh"

titulo "Preparación de la demo"

paso "Herramientas"
requiere aws git curl
[ "$MODO" = aws ] || requiere docker
command -v gitleaks >/dev/null || command -v docker >/dev/null || { mal "Falta gitleaks (o Docker)"; exit 1; }
command -v prowler >/dev/null || command -v docker >/dev/null || { mal "Falta prowler (o Docker)"; exit 1; }
ok "aws, git, curl, gitleaks y prowler disponibles (directo o por Docker)"

# Bajar las imágenes ahora para que no demoren en vivo
imagenes=()
[ "$MODO" = floci ] && imagenes+=("$FLOCI_IMAGE")
command -v gitleaks >/dev/null || imagenes+=("$GITLEAKS_IMAGE")
command -v prowler >/dev/null || imagenes+=("$PROWLER_IMAGE")
for imagen in "${imagenes[@]}"; do
  run docker pull -q "$imagen" >/dev/null
done

if [ "$MODO" = floci ]; then
  paso "Floci: AWS emulado en $FLOCI_URL"
  floci_arrancar
fi

paso "Cuenta"
CUENTA="$(cuenta_actual)"
info "Modo: $MODO   Cuenta: $CUENTA   Región: $REGION   Bucket: $BUCKET"
if [ "$MODO" = aws ]; then
  info "La demo desactiva el bloqueo de acceso público de TODA la cuenta durante el acto 1."
  read -rp "  ¿Es la cuenta aislada de la demo, sin otros datos? (s/N) " resp
  [ "$resp" = s ] || { mal "Cancelado"; exit 1; }
fi
echo "$CUENTA" > "$WORK/cuenta"

paso "Bucket privado con el padrón de clientes ficticio"
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  info "El bucket ya existe"
else
  if [ "$REGION" = us-east-1 ]; then
    crear=(aws s3api create-bucket --bucket "$BUCKET")
  else
    crear=(aws s3api create-bucket --bucket "$BUCKET" --create-bucket-configuration "LocationConstraint=$REGION")
  fi
  run "${crear[@]}" >/dev/null || { mal "No se pudo crear: si el nombre está ocupado, cambiar BUCKET en config.env"; exit 1; }
fi
# Por si quedó abierto de un ensayo anterior
run aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api delete-bucket-policy --bucket "$BUCKET" 2>/dev/null || true
run aws s3 cp --no-progress "datos/$ARCHIVO" "s3://$BUCKET/$ARCHIVO"

paso "Usuario $USUARIO_APP con s3:* sobre todos los recursos"
aws iam get-user --user-name "$USUARIO_APP" >/dev/null 2>&1 || run aws iam create-user --user-name "$USUARIO_APP" >/dev/null
run aws iam put-user-policy --user-name "$USUARIO_APP" --policy-name s3-todo \
  --policy-document "$(politica g10-app-s3-todo.json)"
for clave in $(awsq iam list-access-keys --user-name "$USUARIO_APP" --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
  run aws iam delete-access-key --user-name "$USUARIO_APP" --access-key-id "$clave"
done
cmd "aws iam create-access-key --user-name $USUARIO_APP"
# Las claves de AWS usan base32 (A-Z y 2-7), que es el formato que busca gitleaks.
# Floci las genera con cualquier dígito: se regenera hasta obtener una con el formato real.
for _ in $(seq 1 50); do
  read -r ID SECRETO < <(awsq iam create-access-key --user-name "$USUARIO_APP" \
    --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)
  [[ "$ID" =~ ^AKIA[A-Z2-7]{16}$ ]] && break
  aws iam delete-access-key --user-name "$USUARIO_APP" --access-key-id "$ID"
done
printf 'ID=%s\nSECRETO=%s\n' "$ID" "$SECRETO" > "$WORK/clave-g10-app.env"
ok "Clave $ID guardada en $WORK/clave-g10-app.env (fuera del control de versiones)"

paso "Rol $ROL_LECTURA: solo s3:GetObject sobre el bucket de la demo"
if ! aws iam get-role --role-name "$ROL_LECTURA" >/dev/null 2>&1; then
  run aws iam create-role --role-name "$ROL_LECTURA" \
    --assume-role-policy-document "$(politica g10-app-lectura-confianza.json)" >/dev/null
fi
run aws iam put-role-policy --role-name "$ROL_LECTURA" --policy-name solo-lectura \
  --policy-document "$(politica g10-app-lectura.json)"

if [ "$MODO" = aws ]; then
  paso "Esperando que IAM propague la clave y el rol"
  sleep 15
fi
rm -rf "$WORK/app-g10" "$WORK/atacante" "$WORK/botin"
ok "Listo. Siguiente: ./demo/acto1.sh"

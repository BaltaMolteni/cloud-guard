#!/usr/bin/env bash
# Acto 2 (eje 2, identidades y accesos): la credencial filtrada, como en Uber (2016).
# Romper, mostrar el daño, detectar con gitleaks y corregir: desactivar la clave,
# hook pre-commit y rol de mínimo privilegio.
source "$(dirname "$0")/lib.sh"
verificar_cuenta
source "$WORK/clave-g10-app.env"

APP="$WORK/app-g10"
ATACANTE="$WORK/atacante"
[ -d "$APP/.git" ] || { mal "Falta el repo de la app: correr ./demo/setup.sh"; exit 1; }

# Tapa las claves en pantalla: la pantalla se proyecta.
tapar() { sed -E 's/(= "[^"]{4})[^"]*"/\1••••••••"/'; }

titulo "Acto 2: la credencial filtrada"

paso "0. Punto de partida: el bucket ya es privado"
esperar_http 403
pausa

paso "1. Romper (ya pasó): hace tres semanas la clave de $USUARIO_APP se commiteó en config.py"
run git -C "$APP" log --oneline
info "Al día siguiente se \"sacó\" del código:"
run cat "$APP/config.py"
info "Y el usuario tiene permisos de más:"
run cat politicas/g10-app-s3-todo.json
pausa

paso "2. Mostrar el daño: alguien con acceso de lectura al repositorio"
rm -rf "$ATACANTE" "$WORK/botin"
mkdir -p "$WORK/botin"
run git clone -q "$WORK/remoto/app-g10.git" "$ATACANTE"
(
  # La terminal del atacante: sin perfiles ni credenciales propias, solo lo que hay en el repo.
  unset AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  export AWS_SHARED_CREDENTIALS_FILE="$WORK/sin-credenciales" AWS_CONFIG_FILE="$WORK/sin-credenciales"
  cmd "git -C $ATACANTE log -p | grep AWS_"
  git -C "$ATACANTE" log -p | grep -E '^[-+]AWS_(ACCESS|SECRET)' | tapar
  viejo="$(git -C "$ATACANTE" show HEAD~1:config.py)"
  export AWS_ACCESS_KEY_ID="$(sed -n 's/^AWS_ACCESS_KEY_ID = "\(.*\)"/\1/p' <<< "$viejo")"
  export AWS_SECRET_ACCESS_KEY="$(sed -n 's/^AWS_SECRET_ACCESS_KEY = "\(.*\)"/\1/p' <<< "$viejo")"
  cmd "export AWS_ACCESS_KEY_ID=<id> AWS_SECRET_ACCESS_KEY=<secreto>"
  run aws sts get-caller-identity
  run aws s3 ls
  run aws s3 cp --no-progress "s3://$BUCKET/$ARCHIVO" "$WORK/botin/"
  run head -6 "$WORK/botin/$ARCHIVO"
)
pausa

paso "3. Detectar: gitleaks encuentra la clave en el historial del repositorio"
gitleaks_en "$APP" git -v --redact || true
pausa

paso "4a. Corregir: se desactiva la clave filtrada"
run aws iam update-access-key --user-name "$USUARIO_APP" --access-key-id "$ID" --status Inactive
info "El atacante repite la misma descarga:"
(
  unset AWS_PROFILE AWS_SESSION_TOKEN
  export AWS_SHARED_CREDENTIALS_FILE="$WORK/sin-credenciales" AWS_CONFIG_FILE="$WORK/sin-credenciales"
  export AWS_ACCESS_KEY_ID="$ID" AWS_SECRET_ACCESS_KEY="$SECRETO"
  cmd "aws s3 cp s3://$BUCKET/$ARCHIVO $WORK/botin/"
  # IAM tarda unos segundos en propagar la desactivación.
  for _ in $(seq 1 20); do
    if ! salida="$(aws s3 cp "s3://$BUCKET/$ARCHIVO" "$WORK/botin/" 2>&1)"; then
      echo "$salida"
      exit 0
    fi
    sleep 2
  done
  mal "La clave sigue funcionando: repetir en unos segundos"
)
info "Sacar la clave del código no alcanzó: seguía en el historial. Lo que la anula es desactivarla."
pausa

paso "4b. Prevenir: hook pre-commit con gitleaks"
run cp hooks/pre-commit "$APP/.git/hooks/pre-commit"
chmod +x "$APP/.git/hooks/pre-commit"
info "Alguien vuelve a la configuración anterior, con la clave escrita:"
cmd "git -C $APP show HEAD~1:config.py > $APP/config.py"
git -C "$APP" show HEAD~1:config.py > "$APP/config.py"
if run git -C "$APP" commit -am "Vuelvo a la config anterior"; then
  mal "El commit pasó: revisar el hook"
else
  ok "Commit rechazado por el hook (código de salida $?)"
fi
git -C "$APP" checkout -q config.py
pausa

paso "4c. Mínimo privilegio: la app pasa a usar el rol $ROL_LECTURA"
run cat "${WORK}/politicas/g10-app-lectura.json"
(
  cmd "aws sts assume-role --role-arn arn:aws:iam::$CUENTA:role/$ROL_LECTURA --role-session-name app-g10"
  read -r AK SK ST < <(awsq sts assume-role --role-arn "arn:aws:iam::$CUENTA:role/$ROL_LECTURA" \
    --role-session-name app-g10 --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)
  unset AWS_PROFILE
  export AWS_ACCESS_KEY_ID="$AK" AWS_SECRET_ACCESS_KEY="$SK" AWS_SESSION_TOKEN="$ST"
  info "Credenciales temporales (vencen en 1 hora). La app puede leer su archivo:"
  run aws s3 cp "s3://$BUCKET/$ARCHIVO" "$WORK/botin/rol.csv" >/dev/null && ok "Lectura permitida"
  info "Pero si alguien roba estas credenciales, no puede listar, borrar ni ver otros buckets:"
  run aws s3 ls || true
  run aws s3 rm "s3://$BUCKET/$ARCHIVO" || true
)
ok "Fin del acto 2. Al terminar la presentación: ./demo/limpiar.sh"

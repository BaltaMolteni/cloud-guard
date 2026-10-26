# Guion en vivo

Cómo presentar la demo escribiendo los comandos a mano, como lo haría un administrador real y un atacante real. Los scripts `./demo/acto1.sh` y `./demo/acto2.sh` hacen lo mismo de forma automática y quedan como plan B.

## Antes de la presentación

1. Correr `./demo/setup.sh`. Deja todo como estaría en un caso real:
   - el bucket `g10-demo-datos`, privado, con `clientes_ficticios.csv`;
   - el usuario `g10-app`, con `s3:*` sobre todos los recursos y una clave activa;
   - el repositorio de la app (`.work/app-g10`) y su remoto (`.work/remoto/app-g10.git`). Hace tres semanas alguien commiteó la clave en `config.py`, y al día siguiente la "sacó" del código. La clave sigue en el historial.
2. Abrir **dos ventanas de Git Bash** (menú Inicio → Git Bash, no PowerShell ni el `!` de Claude Code). En cada una, `cd ~/Documentos/src/cloud-guard` y después:

   ```bash
   source demo/terminal.sh admin       # ventana izquierda (prompt verde)
   source demo/terminal.sh atacante    # ventana derecha (prompt rojo)
   ```

   A partir de ahí se escriben comandos reales de `aws`, `git`, `gitleaks` y `prowler`. En modo Floci, la terminal ya apunta al emulador, así que los comandos son idénticos a los de AWS.
3. Dejar abierta una **ventana de incógnito** en el navegador.
4. Agrandar la letra de las terminales.

`$BUCKET` vale `g10-demo-datos` y `$CUENTA` es el ID de la cuenta. Los dos los define `terminal.sh`.

Floci guarda todo en memoria. Si se reinicia la PC o Docker, arranca vacío: `terminal.sh` avisa, y se vuelve a correr `./demo/setup.sh`. Conviene correrlo el mismo día de la presentación, poco antes.

### Qué hace `terminal.sh`

No es un alias. Configura el entorno de esa ventana: con qué credenciales habla `aws`, contra qué endpoint, desde qué carpeta y con qué prompt. No ataca nada: el ataque son los comandos que se escriben después.

En los dos modos:

1. Se mueve a la raíz del proyecto.
2. Exporta `AWS_DEFAULT_REGION` y `AWS_PAGER=""`, para que `aws` no abra un paginador.
3. En `MODO=floci`, exporta `AWS_ENDPOINT_URL=http://localhost:4566`, y todas las llamadas de la CLI van al emulador. En `MODO=aws` no toca el endpoint.
4. Exporta `$BUCKET` y `$CUENTA`.
5. Si gitleaks o Prowler no están instalados, define funciones con esos nombres que corren sus imágenes de Docker, así que el comando que se escribe es el mismo.
6. Avisa si Floci no responde, si está vacío o si falta correr `setup.sh`.

Lo que cambia entre los dos:

| | `admin` | `atacante` |
|---|---|---|
| Credenciales en Floci | `test`/`test`: el administrador (root) de la cuenta emulada `000000000000` | **Ninguna**: borra `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` y `AWS_SESSION_TOKEN` |
| Credenciales en AWS real | El perfil de administrador (`AWS_PROFILE_ADMIN`) | **Ninguna**: borra `AWS_PROFILE` y apunta `AWS_CONFIG_FILE` y `AWS_SHARED_CREDENTIALS_FILE` a un archivo inexistente, para no leer los perfiles de `~/.aws` |
| Endpoint en modo Floci | Floci | Floci también: el emulador hace de "Internet/AWS", y el atacante llega como cualquiera |
| Carpeta | Raíz del proyecto | `.work/atacante-home`, vacía y separada |
| Prompt | `admin` en verde | `atacante` en rojo |

Por eso, en la terminal del atacante, `aws s3 ls` falla con *Unable to locate credentials*. Cuando exporta la clave que encontró en el historial, pasa a ser el usuario `g10-app` de la empresa, como muestra `aws sts get-caller-identity`.

La separación es solo de credenciales, no de máquina ni de red. Las dos ventanas son el mismo usuario de Windows en la misma PC, y desde la del atacante se podría leer `.work/clave-g10-app.env` igual. Es una simulación: el atacante es lo que el presentador elige escribir, partiendo solo del repo clonado.

---

## Acto 1: el bucket público

**Admin: el bucket nace privado**

```bash
aws s3api get-public-access-block --bucket $BUCKET
```

En el navegador de incógnito, abrir la URL del archivo. Responde **403 Access Denied**.

- Floci: `http://localhost:4566/g10-demo-datos/clientes_ficticios.csv`
- AWS: `https://g10-demo-datos.s3.us-east-1.amazonaws.com/clientes_ficticios.csv`

**Admin: romper.** "Lo abro un momento para pasarle el archivo a un proveedor."

```bash
aws s3api delete-public-access-block --bucket $BUCKET
cat politicas/lectura_publica.json
aws s3api put-bucket-policy --bucket $BUCKET --policy file://politicas/lectura_publica.json
```

> En AWS real, si `put-bucket-policy` da AccessDenied, también está activo el bloqueo a nivel de cuenta. Se apaga con:
> `aws s3control delete-public-access-block --account-id $CUENTA`

**Navegador: el daño.** Recargar la pestaña de incógnito: el CSV se descarga sin iniciar sesión, con DNI, tarjetas y CVV.

**Admin: detectar.** El CSPM revisa la cuenta.

```bash
prowler aws --checks s3_bucket_public_access --region us-east-1 --verbose
```

Aparece `FAIL ... S3 Bucket g10-demo-datos has public access due to bucket policy.` con severidad **critical**. Para mostrarlo como panel, abrir el reporte HTML en el navegador:

```bash
start $(ls -t .work/prowler/*.html | head -1)
```

**Admin: corregir.**

```bash
aws s3api put-public-access-block --bucket $BUCKET --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

**Navegador:** recargar. Vuelve a dar **403**, aunque la política con `"Principal": "*"` sigue escrita.

---

## Acto 2: la credencial filtrada

**Atacante: no tiene credenciales**

```bash
aws s3 ls                                   # Unable to locate credentials
```

**Atacante: consigue el repositorio** (un ex empleado, un contratista, un repo que se hizo público por error)

```bash
git clone ../remoto/app-g10.git && cd app-g10
cat config.py                               # parece limpio: lee las claves del entorno
git log --oneline                           # "Saca las claves del código"...
git log -p | grep AWS_                      # ...pero siguen en el historial
```

**Atacante: usa la clave.** Copiar los dos valores que mostró el paso anterior.

```bash
export AWS_ACCESS_KEY_ID=AKIA... AWS_SECRET_ACCESS_KEY=...
aws sts get-caller-identity                 # es el usuario g10-app de la empresa
aws s3 ls                                   # ve todos los buckets: s3:* sobre *
aws s3 cp s3://g10-demo-datos/clientes_ficticios.csv .
head clientes_ficticios.csv
```

El bucket es privado y no importa: tiene una credencial válida.

**Admin: detectar.** Escaneo de secretos sobre el repositorio de la empresa.

```bash
gitleaks git -v --redact .work/app-g10
```

Encuentra la clave (`aws-access-token`) en el commit "Agrega configuración de AWS" de hace tres semanas. Puede aparecer un segundo hallazgo para la clave secreta, según los caracteres que tenga.

**Admin: responder.** Revocar la clave.

```bash
aws iam list-access-keys --user-name g10-app
aws iam update-access-key --user-name g10-app --access-key-id <ID> --status Inactive
```

**Atacante: lo intenta de nuevo**

```bash
aws s3 cp s3://g10-demo-datos/clientes_ficticios.csv .     # 403 / InvalidAccessKeyId
```

**Admin: prevenir.** Hook pre-commit con gitleaks.

```bash
cp hooks/pre-commit .work/app-g10/.git/hooks/
cd .work/app-g10
git show HEAD~1:config.py > config.py       # alguien "vuelve a la config que andaba"
git commit -am "Vuelvo a la config anterior"  # el hook lo rechaza
git checkout config.py
cd ../..
```

**Cierre: mínimo privilegio.** Mostrar `cat politicas/g10-app-lectura.json`: la app debería usar un rol con credenciales temporales y solo `s3:GetObject` sobre su bucket. La prueba completa (lee su archivo, pero `s3 ls` y `s3 rm` dan AccessDenied) está en el paso 4c de `./demo/acto2.sh`.

---

## Dónde se ve cada cosa

| Momento | Dónde mostrarlo |
|---|---|
| Datos expuestos | Ventana de incógnito con la URL del archivo |
| Detección del bucket público | Salida de Prowler y su reporte HTML en `.work/prowler/` |
| Uso de la clave por el atacante | Terminal del atacante (`sts get-caller-identity`, `s3 ls`) |
| Detección de la filtración | Salida de gitleaks: archivo, línea, commit, autor y fecha |
| Revocación | `list-access-keys` antes y después (`Active` → `Inactive`) |

En `MODO=aws` también se puede mostrar la consola de AWS:

- **S3 → Buckets:** la columna *Access* marca el bucket como **Public** mientras está abierto.
- **IAM → Users → g10-app → Security credentials:** las claves de acceso, cuándo se usaron por última vez y el botón **Deactivate**.

Floci tiene una consola web aparte (`docker run -p 4500:4500 floci/floci-ui`, en `http://localhost:4500`). No verificamos que muestre políticas de bucket ni claves de IAM, así que hay que revisarla antes de contar con ella.

## Al terminar

```bash
./demo/limpiar.sh
```

Para repetir el ensayo desde cero alcanza con volver a correr `./demo/setup.sh`.

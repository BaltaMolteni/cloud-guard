# cloud-guard

Demo en vivo de la monografía *Configuraciones erróneas y gestión de identidades: los principales vectores de ataque en la nube pública y cómo mitigarlos* (Grupo 10, Seguridad en Sistemas de Información, UTN FRLP).

La demo prueba las dos mitades de la tesis con datos ficticios. Corre en dos modos:

- **`MODO=floci` (por defecto):** AWS emulado localmente con [Floci](https://floci.io) en Docker. No hace falta cuenta, tarjeta ni Internet durante la presentación.
- **`MODO=aws`:** una cuenta real de AWS, propia y aislada, como describe la monografía.

Los scripts, los comandos que se ven en pantalla y los resultados son los mismos en los dos modos. Tiene dos actos sobre el mismo bucket (`g10-demo-datos`, con `clientes_ficticios.csv`) y los dos siguen la misma secuencia: **romper → mostrar el daño → detectar → corregir**.

| Acto | Eje | Caso real que reproduce | Detecta | Corrige |
|---|---|---|---|---|
| 1. El bucket público | Configuración errónea | Alteryx, LocalBlox, Prestige, JailCore, ESHYFT | Prowler (`s3_bucket_public_access`) | Bloqueo de acceso público |
| 2. La credencial filtrada | Identidades y accesos | Uber (2016) | gitleaks sobre el historial | Desactivar la clave, hook pre-commit, rol de mínimo privilegio |

Dura unos cinco minutos. Todo corre desde scripts para que nadie tenga que tipear en vivo.

## Estructura

```
cloud-guard/
├── config.env               # modo (floci/aws), bucket, región, perfil de AWS, pausas
├── demo/
│   ├── setup.sh             # prepara la cuenta y el repo con la clave filtrada (antes de presentar)
│   ├── terminal.sh          # prepara las terminales de admin y atacante para la demo a mano
│   ├── acto1.sh             # el bucket público, automático (plan B)
│   ├── acto2.sh             # la credencial filtrada, automático (plan B)
│   ├── limpiar.sh           # borra todo al terminar
│   └── lib.sh               # funciones comunes
├── docs/guion-en-vivo.md    # los comandos para presentar a mano, paso a paso
├── politicas/               # las políticas IAM y de bucket que se aplican y se muestran
├── datos/clientes_ficticios.csv
├── app-g10/app.py           # la "aplicación" que termina con la clave en config.py
└── hooks/pre-commit         # hook de gitleaks que se instala en el acto 2
```

Lo que se genera en la demo (la clave de `g10-app`, el repo de la app, el clon del atacante y el archivo descargado) queda en `.work/`, que está en `.gitignore`. **La clave nunca se commitea en este repositorio.**

## Requisitos

Para los dos modos:

- Bash: Git Bash en Windows, o la terminal de Linux o macOS.
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), `git` y `curl` (7.75 o posterior).
- gitleaks y Prowler. Si no están instalados, los scripts usan sus imágenes de Docker.

Según el modo:

- **Floci:** Docker. `setup.sh` levanta el contenedor solo.
- **AWS:** una cuenta separada, sin otros datos y con alerta de presupuesto. El acto 1 desactiva el bloqueo de acceso público de *toda la cuenta* durante unos minutos. Además, un perfil de AWS CLI con permisos de administrador en esa cuenta (`AWS_PROFILE_ADMIN`). El costo es prácticamente cero: un bucket con un archivo de 2 KB y algunas llamadas a la API.

En Windows:

```powershell
winget install Amazon.AWSCLI
winget install Gitleaks.Gitleaks   # opcional si hay Docker
pip install prowler                # opcional si hay Docker
aws configure --profile g10-demo   # solo para MODO=aws
```

## Uso

```bash
# Antes de la presentación: levanta Floci; crea el bucket, el usuario, la clave y el rol;
# arma el repo de la app con la clave en el historial; y descarga las imágenes de Docker.
./demo/setup.sh
```

**En vivo, a mano (recomendado):** dos terminales, una de admin y otra de atacante, donde se escriben los comandos reales de `aws`, `git`, `gitleaks` y `prowler`. Los pasos están en [docs/guion-en-vivo.md](docs/guion-en-vivo.md).

```bash
source demo/terminal.sh admin       # en una ventana
source demo/terminal.sh atacante    # en otra
```

Qué configura cada una (credenciales, endpoint, carpeta) está en [Qué hace `terminal.sh`](docs/guion-en-vivo.md#qué-hace-terminalsh).

**En vivo, automático (plan B):** cada script se detiene entre pasos hasta que se presiona Enter.

```bash
./demo/acto1.sh
./demo/acto2.sh
```

Al terminar:

```bash
./demo/limpiar.sh
```

Para correr sobre AWS real, se antepone el modo a cada script, o se cambia `MODO` en `config.env`:

```bash
MODO=aws AWS_PROFILE_ADMIN=g10-demo ./demo/setup.sh   # pide confirmar que es la cuenta aislada
MODO=aws AWS_PROFILE_ADMIN=g10-demo ./demo/acto1.sh
...
```

- `PAUSA=0 ./demo/acto1.sh` corre todo de corrido. Sirve para ensayar o grabar el video de respaldo.
- `setup.sh` se puede volver a correr para repetir la demo. En Floci arranca un emulador limpio; en AWS deja el bucket cerrado y genera una clave nueva.
- En AWS, los nombres de bucket son únicos en todo el mundo. Si `g10-demo-datos` está ocupado, cambiar `BUCKET` en `config.env`.

### Cómo se hace que Floci se comporte como AWS

Floci, por defecto, acepta cualquier credencial y no evalúa permisos. En ese estado, el bucket privado se puede descargar igual y la demo no prueba nada. `setup.sh` lo arranca con dos opciones:

| Variable | Efecto en la demo |
|---|---|
| `FLOCI_SERVICES_S3_ENFORCE_AUTH=true` | S3 evalúa las políticas de bucket, las ACL y el bloqueo de acceso público, también para pedidos anónimos. Sin esta opción, el acto 1 siempre da 200. |
| `FLOCI_SERVICES_IAM_ENFORCEMENT_ENABLED=true` | Se evalúan las políticas de IAM: la clave desactivada y el rol de solo lectura dan 403. |

Hay otras diferencias, que los scripts resuelven solos:

- En Floci, la URL pública es `http://localhost:4566/g10-demo-datos/clientes_ficticios.csv` y la cuenta es `000000000000`.
- La CLI no puede llegar a S3 Control en Floci porque arma el host `<cuenta>.localhost`. El bloqueo a nivel de cuenta se envía a la misma API con `curl --aws-sigv4`, y en pantalla se muestra el comando de AWS CLI equivalente.
- Floci genera claves con cualquier dígito, pero las de AWS solo usan A-Z y 2-7, que es el formato que busca gitleaks. `setup.sh` regenera la clave hasta que tenga el formato real.

Probado con Floci 2.3.0, Prowler 5.45 y gitleaks 8.21.2.

## Guion

### Acto 1: el bucket público (eje 1)

| Paso | Qué pasa en pantalla | Qué decimos |
|---|---|---|
| 0 | El archivo responde 403. | Un bucket nace privado. |
| 1. Romper | Se borra el bloqueo de acceso público (cuenta y bucket) y se aplica la política con `"Principal": "*"`. | Son dos comandos, o tres clics en la consola. Es el "lo abro un momento para compartir un archivo" que nadie vuelve a cerrar. |
| 2. Daño | Se abre la URL en una ventana de incógnito y el CSV se descarga con DNI, tarjetas y CVV. | No hubo que vulnerar nada. Así quedaron Prestige (tarjetas con CVV) y ESHYFT. Hay escáneres que prueban nombres de buckets de forma masiva. |
| 3. Detectar | Prowler marca `s3_bucket_public_access` en **FAIL**, con severidad crítica. | Es la capa 4 (CSPM): encuentra en un minuto lo que las empresas tardaron meses en notar. |
| 4. Corregir | Se reactiva el bloqueo y la misma URL devuelve **403**. | La política pública sigue escrita, pero el bloqueo la anula. Es la capa 1, y AWS la activa por defecto en los buckets nuevos desde 2023. |

### Acto 2: la credencial filtrada (eje 2)

| Paso | Qué pasa en pantalla | Qué decimos |
|---|---|---|
| 0 | El bucket ya es privado (403). | Cerramos el bucket. ¿Alcanza? |
| 1. Romper (ya pasó) | Hace tres semanas, la clave de `g10-app` se commiteó en `config.py`. Al día siguiente se "sacó" del código. El usuario tiene `s3:*` sobre `*`. | Es lo mismo que hizo Uber en 2016. Permisos de más "para que funcione". |
| 2. Daño | Sin credenciales propias, el atacante clona el repo, encuentra la clave en el historial (`git log -p`) y descarga el CSV privado. | La identidad reemplaza al perímetro: quien tiene la clave entra desde cualquier lugar. |
| 3. Detectar | gitleaks encuentra la clave en el historial, con el commit, el autor y la fecha. Según los caracteres de la clave secreta, puede aparecer un segundo hallazgo. | Es la capa 5 (DevSecOps). |
| 4a. Corregir | Se desactiva la clave y la misma descarga falla con 403. | Sacar la clave del código no alcanzó: seguía en el historial. Hay que revocarla. |
| 4b. Prevenir | Se instala el hook pre-commit. Alguien vuelve a la configuración anterior, que tiene la clave escrita, y el commit se rechaza (código de salida 1). | El error no llega al repositorio. |
| 4c. Mínimo privilegio | La app asume el rol `g10-app-lectura`, que tiene credenciales temporales y solo `s3:GetObject`. Lee su archivo, pero `s3 ls` y `s3 rm` dan AccessDenied. | Es la capa 0. Si estas credenciales se filtran, vencen en una hora y no sirven para nada más. Le habría puesto un límite a Capital One. |

## Plan B

- Si falla la conexión en `MODO=aws`, pasar a `MODO=floci`, que no necesita Internet una vez descargadas las imágenes. Como último recurso, pasar el video grabado con `PAUSA=0`.
- Correr `setup.sh` antes de la presentación: descarga las imágenes de Docker. La de Prowler es grande y la primera descarga tarda unos minutos.
- Si IAM o S3 tardan en propagar un cambio, los scripts reintentan solos durante unos 30 a 40 segundos.

## Uso ético

Solo en el emulador o en una cuenta propia, y con datos ficticios. Las tarjetas del CSV son números de prueba públicos y los DNI y correos son inventados. Al terminar, `limpiar.sh` borra el contenedor de Floci o, en AWS, el usuario, la clave, el rol y el bucket, y deja activado el bloqueo de acceso público de la cuenta.

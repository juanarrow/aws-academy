# Desplegar el pipeline con Terraform

Esta guía explica cómo se crea en AWS el pipeline de la práctica y qué hace cada fichero de la carpeta. No hace falta haber usado Terraform antes.

Al terminar tendrás dos buckets de S3 y una Lambda:

```
tú subes un CSV
        │
        ▼
s3://…-raw-…/ventas.csv          ← bucket de entrada
        │  AWS avisa a la Lambda solo si el nombre acaba en .csv
        ▼
Lambda (Python + pandas)         ← limpia el fichero
        │
        ▼
s3://…-limpio-…/ventas.parquet   ← bucket de salida
```

La limpieza (quitar vacíos, duplicados, pasar tipos) está en `lambda/limpieza.py`. Terraform no limpia datos: solo crea los buckets, la Lambda y la notificación de «ha llegado un fichero».

Cada alumno despliega en **su** cuenta del Learner Lab. Lo que crees tú no aparece en la cuenta de otro.

## Terraform, en corto

Terraform lee unos ficheros de texto (`.tf`) que describen lo que quieres que exista en AWS. Compara esa descripción con lo que ya hay en la cuenta y crea lo que falta.

Tres comandos, siempre desde esta carpeta:

| Comando | Qué hace |
|---|---|
| `terraform init` | Descarga los plugins. Se lanza una vez, o cuando cambian los ficheros de versiones. |
| `terraform apply` | Crea (o actualiza) la Lambda y la notificación de S3. Los buckets ya existen: los creaste en la consola. Pide confirmación: hay que escribir `yes`. |
| `terraform destroy` | Borra la Lambda, la notificación y los logs. Los buckets se quedan. También pide `yes`. |

Terraform guarda en `terraform.tfstate` la lista de lo que ha creado. Gracias a esa lista, `destroy` sabe qué borrar. No borres ese fichero a mano y no lo subas a git: está en `.gitignore`.

Los comandos de esta guía se escriben en la terminal de **WSL** (Ubuntu dentro de Windows), no en PowerShell ni en el símbolo del sistema. Terraform tiene que estar instalado en esa Ubuntu.

## El editor

En Cursor (o VS Code) instala la extensión **HashiCorp Terraform**, identificador `HashiCorp.terraform`. Colorea los `.tf` y completa mientras escribes: el tipo de recurso, argumentos como `byte_length` y un aviso si el argumento no existe. Al abrir esta carpeta, abajo a la derecha del editor pone **Terraform**.

Esa extensión usa el comando `terraform` para el autocompletado. Si Terraform está instalado solo en Ubuntu, abre la carpeta del proyecto con **Remote - WSL**. Cursor abierto en Windows, sin esa conexión, no ve el binario de Ubuntu y el coloreado funciona, pero el autocompletado no.

## Antes de desplegar

1. Entra en la clase del laboratorio (en este curso se llama **ETL**).
2. **Contenidos** → **Lanzamiento del Laboratorio para el alumnado de AWS Academy**.
3. Pulsa **Start Lab** y espera a que el indicador se ponga verde. La primera vez puede tardar varios minutos.
4. **AWS Details** → **Show** junto a **AWS CLI**. Copia el bloque entero (en Windows: Ctrl+C).
5. En la terminal de WSL, sitúate en esta carpeta y pega el bloque. En Windows Terminal el pegado es Ctrl+Shift+V o clic derecho:

```bash
git clone https://github.com/juanarrow/pipeline-csv-parquet.git
cd pipeline-csv-parquet
cat > credentials << 'EOF'
```

Pega aquí el bloque, en una línea nueva escribe `EOF` y pulsa Enter. El fichero queda así (las claves reales son mucho más largas):

```ini
[default]
aws_access_key_id=ASIA...
aws_secret_access_key=...
aws_session_token=...
```

Windows a veces pega con retornos de carro. Quítalos y comprueba que el token está:

```bash
sed -i 's/\r$//' credentials
grep -c aws_session_token credentials
```

El `grep` tiene que devolver `1`.

6. En **esa misma terminal**, indica que Terraform use este fichero y la región del laboratorio:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE
export AWS_SHARED_CREDENTIALS_FILE="$PWD/credentials"
export AWS_DEFAULT_REGION=us-east-1
```

`unset` solo afecta a esta terminal. No modifica otras ventanas. Al cerrarla, el efecto desaparece.

Las credenciales caducan cuando el indicador deja de estar verde o al pulsar **End Lab** (unas 4 horas). Si un comando responde `ExpiredToken`, repite el paso 5 con un bloque nuevo de **AWS Details**.

## Los ficheros, uno a uno

Terraform junta todos los `.tf` de la carpeta. El nombre del fichero no cambia el orden de creación: se separan para poder leerlos. Este es el orden en el que conviene leerlos.

### `versions.tf` — qué programas hacen falta

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.6"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
```

Un **provider** es un plugin. Terraform solo no sabe crear un bucket de S3: el plugin `aws` sí.

| Plugin | Para qué está |
|---|---|
| `aws` | Buckets, Lambda, permisos, logs. |
| `archive` | Comprime la carpeta `lambda/` en un `.zip`, que es el formato que exige Lambda. |
| `random` | Genera un sufijo aleatorio para el nombre de la Lambda, y así no choca si se vuelve a crear. |

`>= 1.5.0` significa «Terraform 1.5 o más nuevo». `~> 6.0` significa «la versión 6, cualquiera de la serie 6». Al hacer `init`, Terraform anota la versión exacta que ha descargado en `.terraform.lock.hcl`, para que todo el grupo use la misma.

### `variables.tf` — los valores que se pueden cambiar

Una `variable` es un hueco con un valor por defecto. El resto de ficheros la usa como `var.nombre`. Si no cambias nada, valen los defaults y el despliegue funciona.

| Variable | Default | Qué controla |
|---|---|---|
| `aws_region` | `us-east-1` | Región. En el laboratorio solo valen `us-east-1` y `us-west-2`. |
| `credentials_file` | `./credentials` | Dónde está el bloque copiado de **AWS Details**. |
| `prefijo` | `bigdata` | Empieza el nombre de los buckets y de la Lambda. Solo minúsculas, números y guiones. |
| `pandas_layer_arn` | vacío | Capa con pandas. Vacío: se usa la capa pública de AWS. |
| `memoria_mb` | `1024` | Memoria de la Lambda. Pandas pide holgura aunque el CSV sea pequeño. |
| `timeout_segundos` | `60` | Tiempo máximo de una ejecución. Si se pasa, AWS corta la función. |

Los bloques `validation` rechazan un valor imposible antes de tocar AWS. Por ejemplo, una región distinta de las dos del laboratorio, o un prefijo con mayúsculas.

Para cambiar un default sin editar el fichero, crea `terraform.tfvars` (puedes copiar `terraform.tfvars.example`):

```hcl
prefijo = "grupo3"
```

### `providers.tf` — con qué cuenta habla Terraform

```hcl
provider "aws" {
  region                   = var.aws_region
  shared_credentials_files = [pathexpand(var.credentials_file)]
}
```

Aquí se enchufa el plugin de AWS: región `us-east-1` y el fichero `credentials` de esta carpeta. Terraform no usa las claves que puedas tener en `~/.aws`, salvo que la terminal tenga variables `AWS_ACCESS_KEY_ID` o `AWS_PROFILE`. Por eso el paso 6 del inicio las quita en esta terminal.

Debajo hay un bloque `data`, que no crea nada. Lee algo que **ya existe** en la cuenta:

```hcl
data "aws_iam_role" "lab" {
  name = "LabRole"
}
```

`LabRole` lo crea el Learner Lab. Es el permiso con el que la Lambda podrá leer el bucket de entrada y escribir el de salida. En esta cuenta no se pueden crear roles nuevos: cualquier `resource "aws_iam_role"` fallaría. Por eso la función, más adelante, recibe `data.aws_iam_role.lab.arn` (el identificador de ese rol ya existente).

### `main.tf` — lo que se crea

Este es el fichero largo. Cada bloque `resource` es una cosa que Terraform crea en AWS. El texto entre comillas (`"aws_s3_bucket" "raw"`) es el tipo y un nombre **interno**: el nombre interno sirve para citarlo desde otro bloque (`aws_s3_bucket.raw.id`). El nombre que se ve en la consola de AWS es otro, el del argumento `bucket` o `function_name`.

#### Nombres

```hcl
resource "random_id" "sufijo" {
  byte_length = 3
}
```

Genera unos caracteres al azar, por ejemplo `a1b2c3`. La Lambda se llama `bigdata-limpieza-csv-a1b2c3`. El bloque `locals` guarda ese nombre para no repetirlo. Los buckets no salen de aquí: los creas tú en la consola y pasas el nombre en `terraform.tfvars`.

#### Los dos buckets

El CSV entra en el bucket `bucket_raw`. El Parquet sale en `bucket_limpio`. Son dos para que el fichero de salida no vuelva a disparar la Lambda.

Los creas en la consola, antes del `apply`. Terraform solo recibe el nombre, en `variables.tf`:

```hcl
variable "bucket_raw" {
  type = string
}

variable "bucket_limpio" {
  type = string
}
```

En `main.tf` se usan como `var.bucket_raw` y `var.bucket_limpio`. El recurso `aws_s3_bucket` no está en este proyecto: al refrescar el estado lee Object Lock, y el Learner Lab deniega esa lectura.

Al crear cada bucket en la consola, en **N. Virginia**:

1. **S3** → **Create bucket**.
2. Nombre único en todo AWS. Por ejemplo `ana-raw-2026` y `ana-limpio-2026`. Minúsculas, números y guiones.
3. Deja marcado **Block all public access**.
4. En cifrado, deja **SSE-S3** (claves gestionadas por Amazon S3).
5. Crea el segundo bucket igual.

Escribe los dos nombres en `terraform.tfvars` (copia `terraform.tfvars.example`). Ese fichero no se sube a git.

`terraform destroy` borra la Lambda y la notificación. Los buckets se quedan: se borran en la consola, vaciándolos antes si aún tienen ficheros.

#### El zip de la función

```hcl
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/build/handler.zip"
}
```

Otro `data`: no crea nada en AWS. Comprime `lambda/handler.py` y `lambda/limpieza.py` en `build/handler.zip`. Lambda no acepta una carpeta suelta, solo un zip. La carpeta `build/` está en `.gitignore`.

#### Los logs

```hcl
resource "aws_cloudwatch_log_group" "limpieza" {
  name              = "/aws/lambda/${local.nombre_lambda}"
  retention_in_days = 7
}
```

CloudWatch guarda lo que la función imprime (`print`). El grupo se crea antes que la función y los logs se borran a los 7 días, para no acumular coste en el crédito de 100 USD.

#### La Lambda

```hcl
resource "aws_lambda_function" "limpieza" {
  function_name = local.nombre_lambda
  role          = data.aws_iam_role.lab.arn
  runtime       = "python3.12"
  handler       = "handler.lambda_handler"
  filename      = data.archive_file.lambda.output_path
  layers        = [local.pandas_layer_arn]
  memory_size   = var.memoria_mb
  timeout       = var.timeout_segundos

  environment {
    variables = {
      DEST_BUCKET = var.bucket_limpio
    }
  }
}
```

| Argumento | Significado |
|---|---|
| `role` | El `LabRole` que ya existía. Sin este rol la función no puede leer ni escribir S3. |
| `runtime` | El intérprete de Python que usa AWS. |
| `handler` | Fichero `handler`, función `lambda_handler`. Es el punto de entrada cuando S3 la invoca. |
| `filename` | El zip del paso anterior. |
| `source_code_hash` | La huella del zip. Si cambias el Python y vuelves a hacer `apply`, Terraform ve que la huella es distinta y actualiza la función. |
| `layers` | Pandas y pyarrow. El Python de Lambda no los trae. La capa es un zip público de AWS (AWS SDK for pandas, Python 3.12). |
| `memory_size` y `timeout` | Las variables de `variables.tf`. |
| `DEST_BUCKET` | Variable de entorno dentro de la función: el nombre del bucket donde debe escribir el Parquet. El código la lee con `os.environ["DEST_BUCKET"]`. |

#### La notificación «ha llegado un CSV»

Hacen falta dos recursos, en este orden:

```hcl
resource "aws_lambda_permission" "s3" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.limpieza.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${var.bucket_raw}"
}
```

Esto autoriza al bucket `raw` a invocar la Lambda. Sin este permiso, S3 intentaría avisarla y AWS lo rechazaría.

```hcl
resource "aws_s3_bucket_notification" "raw" {
  bucket = var.bucket_raw

  lambda_function {
    lambda_function_arn = aws_lambda_function.limpieza.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.s3, aws_cloudformation_stack.buckets]
}
```

Cada vez que se crea un objeto en `raw` cuyo nombre acaba en `.csv`, S3 llama a la Lambda. `depends_on` obliga a crear antes el permiso: si la notificación se creara primero, AWS lo rechaza.

`ObjectCreated:*` cubre cualquier subida: la consola, un programa o la AWS CLI si estuviera instalada.

### `outputs.tf` — lo que Terraform imprime al acabar

Un `output` no crea nada. Es un valor que `apply` muestra al final y que luego se puede consultar:

```bash
terraform output -raw bucket_raw
terraform output -raw bucket_limpio
terraform output -raw funcion
terraform output -raw comando_prueba
```

| Output | Qué es |
|---|---|
| `bucket_raw` | Nombre del bucket donde subes el CSV. |
| `bucket_limpio` | Nombre del bucket donde aparece el Parquet. |
| `funcion` | Nombre de la Lambda, para buscar sus logs. |
| `comando_prueba` | Un `aws s3 cp` ya escrito con el nombre real de tu bucket. Solo sirve si tienes AWS CLI instalado. En clase el CSV se sube desde la consola. |

El nombre de la Lambda lleva el sufijo aleatorio. Los buckets son los que escribiste en `terraform.tfvars`.

## Los ficheros que no son Terraform

| Fichero | Qué es |
|---|---|
| `lambda/limpieza.py` | La limpieza con pandas. Se puede probar en local, sin AWS: `python lambda/limpieza.py`. |
| `lambda/handler.py` | Recibe la notificación de S3, llama a `limpiar` y escribe el Parquet en el otro bucket. |
| `datos/ventas_sucio.csv` | CSV pequeño para ver la limpieza: fila vacía, duplicado, espacios y un `no-num`. |
| `datos/ventas_almacen_2019.csv` | Ventas reales de 2019 (138 638 filas, dominio público). Para consultar en Athena y graficar. |
| `credentials` | Tus claves del laboratorio. No se sube a git. |
| `.terraform.lock.hcl` | Versiones exactas de los plugins. Sí se guarda. |
| `.terraform/` | Plugins descargados por `init`. No se sube. |
| `terraform.tfstate` | Lista de lo creado en tu cuenta. No se sube. Si la pierdes, `destroy` ya no sabe qué borrar. |
| `build/` | El zip de la Lambda. Lo regenera `apply`. |

## Desplegar

Con el laboratorio en verde y `credentials` ya creado:

```bash
cd pipeline-csv-parquet
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE
export AWS_SHARED_CREDENTIALS_FILE="$PWD/credentials"
export AWS_DEFAULT_REGION=us-east-1

terraform init
terraform apply
```

`init` solo hace falta la primera vez en esa carpeta. `apply` enseña un plan (qué va a crear) y espera a que escribas `yes`.

Tarda un minuto. Al acabar, la terminal muestra los cuatro outputs.

## Probarlo

No hace falta tener AWS CLI. La subida se hace desde la consola del navegador.

1. Anota los nombres:

```bash
terraform output
```

2. En la página del laboratorio, pulsa el botón **AWS** (el indicador tiene que seguir verde). Se abre la consola.
3. Arriba a la derecha, la región tiene que ser **N. Virginia** (`us-east-1`). Si pone otra, cámbiala: en otra región los buckets no aparecen.
4. Busca **S3** y entra en el bucket cuyo nombre es el output `bucket_raw`.
5. **Upload** → **Add files**. El cuadro de Windows no siempre ve las carpetas de WSL. Desde la terminal del proyecto ábrelas en el Explorador:

```bash
explorer.exe datos
```

Para comprobar la limpieza, elige `ventas_sucio.csv`. Para un volumen real, `ventas_almacen_2019.csv` (unos 13 MB). El nombre tiene que acabar en `.csv`.
6. Espera unos segundos y abre el bucket `bucket_limpio`. Aparece el mismo nombre con extensión `.parquet`. El pequeño tarda un momento; el de 2019, cerca de un minuto.
7. Para ver cuántas filas han entrado y cuántas han salido: en la consola, busca **CloudWatch** → **Log groups** → `/aws/lambda/` seguido del output `funcion`. Abre el log stream más reciente. El de ejemplo entra con 8 filas y sale con 6.

El Parquet aparece en el bucket limpio cuando el CSV está en el bucket `raw`, el nombre acaba en `.csv` y la región es `us-east-1`.

## Quitar lo creado

El crédito del laboratorio es de unos 100 USD para toda la clase. Esta práctica, parada, gasta muy poco (los buckets solo cobran por lo que almacenan). Aun así, al acabar:

```bash
terraform destroy
```

Escribe `yes`. Borra la Lambda, la notificación y los logs. Los buckets siguen en la consola: vacíalos y bórralos allí cuando ya no hagan falta.

En la página del laboratorio, **End Lab** apaga la sesión de 4 horas. No borra lo que Terraform ha creado: eso sigue en la cuenta hasta el `destroy` o hasta la fecha de fin de la clase.

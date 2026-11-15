# Pipeline CSV → Parquet (AWS Academy)

La guía para quien no ha usado Terraform está en [despliegue.md](despliegue.md).

Subes un CSV a un bucket de S3. Una Lambda salta sola, limpia el fichero y deja un Parquet en otro bucket.

Pensado para **AWS Academy Learner Lab**: no crea roles de IAM (usa `LabRole`), región `us-east-1` o `us-west-2`, y los buckets se pueden vaciar con `terraform destroy`.

```
CSV  →  s3://…-raw-…/fichero.csv
              │  evento ObjectCreated (*.csv)
              ▼
        Lambda (pandas, rol LabRole)
              │  nombres, textos, vacíos, duplicados, tipos
              ▼
        s3://…-limpio-…/fichero.parquet
```

El Parquet queda ahí para el paso siguiente (Athena, un notebook, un gráfico). Este proyecto se para en la limpieza.

## Qué hace la limpieza

La lógica está en `lambda/limpieza.py` y se puede probar sin AWS. Sobre cada CSV:

1. Detecta separador coma o punto y coma.
2. Normaliza los nombres de columna (minúsculas, sin acentos, espacios a `_`).
3. Recorta textos y convierte vacíos y `n/a` en nulos.
4. Quita filas totalmente vacías y filas duplicadas.
5. Interpreta como fecha las columnas cuyo nombre contiene `fecha`, en formato `YYYY-MM-DD` o `DD/MM/YYYY`.
6. Pasa a número una columna si al menos el 80 % de sus valores convierten. El resto de esa columna queda nulo.

Con `datos/ventas_sucio.csv` el resultado son 6 filas: desaparecen el duplicado de manzanas y la fila vacía; `ventas` pasa a número y `no-num` queda nulo; `región` pasa a llamarse `region`.

`datos/ventas_almacen_2019.csv` es el caso realista: 138 638 filas de ventas mensuales de 2019 (enero a noviembre) del Departamento de Control de Licores del condado de Montgomery, Maryland. Dominio público, [Warehouse and Retail Sales](https://catalog.data.gov/dataset/warehouse-and-retail-sales). Se ha añadido la columna `fecha` (día 1 de ese mes) para que la limpieza la interprete como fecha. El portal publica más años, con meses vacíos; 2019 es el tramo seguido. `item_code` es casi todo números, así que la regla del 80 % lo pasa a numérico y 23 códigos con letras quedan nulos.

## Requisitos

- Terraform >= 1.5, instalado en WSL (Ubuntu), no en PowerShell
- Lab de AWS Academy arrancado
- Python 3.12 solo si quieres probar la limpieza en local (`pandas` y `pyarrow`)
- AWS CLI no hace falta: el CSV se sube desde la consola

## 1. Credenciales del lab

En Learner Lab: **Start Lab** → **AWS Details** → **AWS CLI** → Show. Pega el bloque entero en `credentials` dentro de esta carpeta (el fichero está en `.gitignore`):

```ini
[default]
aws_access_key_id=...
aws_secret_access_key=...
aws_session_token=...
```

Caducan a las pocas horas. Si `apply` responde `ExpiredToken`, vuelve a pegar el bloque.

En la misma terminal, evita que otras credenciales pisen las del lab:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE
export AWS_SHARED_CREDENTIALS_FILE="$PWD/credentials"
export AWS_DEFAULT_REGION=us-east-1
```

## 2. Probar la limpieza en local

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install pandas pyarrow
python lambda/limpieza.py
```

## 3. Desplegar

```bash
terraform init
terraform apply
```

Crea el grupo de logs (retención 7 días), la Lambda y la notificación de S3. Los dos buckets se crean antes, en la consola, y sus nombres van en `terraform.tfvars`. La Lambda usa la capa pública [AWS SDK for pandas](https://aws-sdk-pandas.readthedocs.io/en/stable/layers.html) (Python 3.12, x86_64), que trae `pandas` y `pyarrow`. El runtime de Lambda no los incluye.

## 4. Lanzar un fichero

Desde la consola, sin AWS CLI. `terraform output` da el nombre de cada bucket. En la página del laboratorio pulsa **AWS**, deja la región en **N. Virginia** (`us-east-1`), abre el bucket `bucket_raw` y sube `datos/ventas_sucio.csv` (**Upload**). Si el cuadro de Windows no ve la carpeta de WSL:

```bash
explorer.exe datos
```

A los pocos segundos, `ventas_sucio.parquet` está en el bucket `bucket_limpio`. El recuento de filas (8 de entrada, 6 de salida) está en CloudWatch → Log groups → `/aws/lambda/` más el output `funcion`.

Quien tenga AWS CLI puede usar el output `comando_prueba`.

Solo disparan la función las claves que terminan en `.csv`. El destino es otro bucket, así que el Parquet no vuelve a lanzar la Lambda.

## 5. Apagar

```bash
terraform destroy
```

`terraform destroy` quita la Lambda y la notificación. Los buckets se borran en la consola. La Lambda parada no cobra; el crédito del lab es de unos 100 USD para todo el curso.

## Límites del lab

- Ficheros de clase, del orden de decenas de MB. Un CSV grande no cabe en 1024 MB y 60 s. Se suben en `terraform.tfvars` con `memoria_mb` y `timeout_segundos`.
- Si al crear la Lambda aparece `lambda:GetLayerVersion` denegado sobre la cuenta `336392948345`, el lab bloquea la capa pública. Construye una propia y pasa su ARN:

  ```bash
  ./scripts/construir-capa.sh
  aws lambda publish-layer-version \
    --layer-name pandas-pyarrow \
    --zip-file fileb://build/capa-pandas.zip \
    --compatible-runtimes python3.12 \
    --compatible-architectures x86_64
  ```

  Si el zip supera 50 MB, súbelo antes a un bucket y usa `--content S3Bucket=...,S3Key=...` en lugar de `--zip-file`. Luego:

  ```hcl
  # terraform.tfvars
  pandas_layer_arn = "arn:aws:lambda:us-east-1:TU_CUENTA:layer:pandas-pyarrow:1"
  ```

- No añadas `aws_iam_role`. Learner Lab lo rechaza. Cualquier permiso extra tiene que salir de `LabRole`.

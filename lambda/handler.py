"""Se dispara al subir un CSV a S3, lo limpia y escribe un Parquet en el otro bucket."""

import os
import urllib.parse
from io import BytesIO

import boto3

from limpieza import leer_csv, limpiar

DEST_BUCKET = os.environ["DEST_BUCKET"]
s3 = boto3.client("s3")


def lambda_handler(event, context):
    procesados = []
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        if not key.lower().endswith(".csv"):
            print(f"Se ignora {key}: no termina en .csv")
            continue
        procesados.append(procesar_objeto(bucket, key))
    return {"procesados": procesados}


def procesar_objeto(bucket, key):
    contenido = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
    entrada = leer_csv(contenido)
    limpio = limpiar(entrada)

    destino = f"{key.rsplit('.', 1)[0]}.parquet"
    buffer = BytesIO()
    limpio.to_parquet(buffer, index=False)
    s3.put_object(
        Bucket=DEST_BUCKET,
        Key=destino,
        Body=buffer.getvalue(),
        ContentType="application/vnd.apache.parquet",
    )

    resumen = {
        "origen": f"s3://{bucket}/{key}",
        "destino": f"s3://{DEST_BUCKET}/{destino}",
        "filas_entrada": len(entrada),
        "filas_salida": len(limpio),
    }
    print(resumen)
    return resumen

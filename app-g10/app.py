"""Aplicación de ejemplo de la demo: descarga el padrón de clientes desde S3."""
import boto3

import config

s3 = boto3.client(
    "s3",
    region_name=config.AWS_REGION,
    aws_access_key_id=config.AWS_ACCESS_KEY_ID,
    aws_secret_access_key=config.AWS_SECRET_ACCESS_KEY,
)
s3.download_file(config.BUCKET, "clientes_ficticios.csv", "clientes.csv")
print("Padrón descargado en clientes.csv")

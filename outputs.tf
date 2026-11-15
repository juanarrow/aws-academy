output "bucket_raw" {
  description = "Bucket donde se sube el CSV."
  value       = var.bucket_raw
}

output "bucket_limpio" {
  description = "Bucket donde la Lambda deja el Parquet."
  value       = var.bucket_limpio
}

output "funcion" {
  description = "Nombre de la Lambda de limpieza."
  value       = aws_lambda_function.limpieza.function_name
}

output "comando_prueba" {
  description = "Sube el CSV de ejemplo y dispara la Lambda."
  value       = "aws s3 cp datos/ventas_sucio.csv s3://${var.bucket_raw}/ventas_sucio.csv"
}

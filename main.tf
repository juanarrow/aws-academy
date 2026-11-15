locals {
  sufijo        = random_id.sufijo.hex
  nombre_lambda = "${var.prefijo}-limpieza-csv-${local.sufijo}"

  # Capa pública AWS SDK for pandas, Python 3.12, x86_64.
  # https://aws-sdk-pandas.readthedocs.io/en/stable/layers.html
  capas_publicas = {
    us-east-1 = "arn:aws:lambda:us-east-1:336392948345:layer:AWSSDKPandas-Python312:32"
    us-west-2 = "arn:aws:lambda:us-west-2:336392948345:layer:AWSSDKPandas-Python312:32"
  }
  pandas_layer_arn = var.pandas_layer_arn != "" ? var.pandas_layer_arn : local.capas_publicas[var.aws_region]
}

resource "random_id" "sufijo" {
  byte_length = 3
}

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/build/handler.zip"
  excludes    = ["__pycache__", "*.pyc"]
}

resource "aws_cloudwatch_log_group" "limpieza" {
  name              = "/aws/lambda/${local.nombre_lambda}"
  retention_in_days = 7
}

resource "aws_lambda_function" "limpieza" {
  function_name    = local.nombre_lambda
  role             = data.aws_iam_role.lab.arn
  runtime          = "python3.12"
  architectures    = ["x86_64"]
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  layers           = [local.pandas_layer_arn]
  memory_size      = var.memoria_mb
  timeout          = var.timeout_segundos

  environment {
    variables = {
      DEST_BUCKET = var.bucket_limpio
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.limpieza.name
  }

  depends_on = [aws_cloudwatch_log_group.limpieza]
}

resource "aws_lambda_permission" "s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.limpieza.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${var.bucket_raw}"
}

resource "aws_s3_bucket_notification" "raw" {
  bucket = var.bucket_raw

  lambda_function {
    lambda_function_arn = aws_lambda_function.limpieza.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.s3]
}

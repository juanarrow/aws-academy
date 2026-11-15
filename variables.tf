variable "aws_region" {
  description = "Región del Learner Lab."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-west-2"], var.aws_region)
    error_message = "En Learner Lab usa us-east-1 o us-west-2."
  }
}

variable "credentials_file" {
  description = "Fichero con el bloque AWS CLI de AWS Details. No se versiona."
  type        = string
  default     = "./credentials"
}

variable "prefijo" {
  description = "Prefijo de buckets y de la función. Minúsculas, números y guiones."
  type        = string
  default     = "bigdata"

  validation {
    condition     = length(var.prefijo) >= 2 && length(var.prefijo) <= 20 && can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.prefijo))
    error_message = "Prefijo de 2 a 20 caracteres: minúsculas, números y guiones, sin empezar ni acabar en guion."
  }
}

variable "pandas_layer_arn" {
  description = "Capa con pandas y pyarrow. Vacío usa la capa pública de AWS SDK for pandas (Python 3.12, x86_64) de la región elegida."
  type        = string
  default     = ""
}

variable "memoria_mb" {
  description = "Memoria de la Lambda. pandas necesita holgura aunque el CSV sea pequeño."
  type        = number
  default     = 1024
}

variable "timeout_segundos" {
  description = "Tiempo máximo de la Lambda."
  type        = number
  default     = 60
}

variable "bucket_raw" {
  description = "Nombre del bucket de entrada, creado antes en la consola de S3."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_raw))
    error_message = "Nombre de bucket: 3-63 caracteres, minúsculas, números, puntos y guiones."
  }
}

variable "bucket_limpio" {
  description = "Nombre del bucket de salida, creado antes en la consola de S3."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_limpio))
    error_message = "Nombre de bucket: 3-63 caracteres, minúsculas, números, puntos y guiones."
  }
}

provider "aws" {
  region                   = var.aws_region
  shared_credentials_files = [pathexpand(var.credentials_file)]
}

# Learner Lab no deja crear roles. LabRole ya existe y puede leer y escribir S3.
data "aws_iam_role" "lab" {
  name = "LabRole"
}

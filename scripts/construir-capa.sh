#!/bin/bash
# Capa de respaldo si Learner Lab deniega la capa pública de AWS SDK for pandas.
# Genera build/capa-pandas.zip para Python 3.12 en Lambda x86_64.
set -euo pipefail

raiz="$(cd "$(dirname "$0")/.." && pwd)"
destino="$raiz/build/capa"
rm -rf "$destino"
mkdir -p "$destino/python"

pip3 install \
  --platform manylinux2014_x86_64 \
  --target "$destino/python" \
  --implementation cp \
  --python-version 3.12 \
  --only-binary=:all: \
  pandas pyarrow

(cd "$destino" && zip -qr "$raiz/build/capa-pandas.zip" python)
echo "Zip listo: $raiz/build/capa-pandas.zip"
echo "Si pesa más de 50 MB, publícalo pasando por S3. El comando directo está en el README."

"""Limpieza de un CSV, la misma lógica que en la sesión 04, sin AWS."""

import unicodedata
from io import BytesIO

import pandas as pd

# Una columna pasa a numérica si al menos esta fracción de sus valores convierte.
UMBRAL_NUMERICO = 0.8
AUSENTES = {"", "nan", "none", "null", "n/a", "na"}
FORMATOS_FECHA = ("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y")


def leer_csv(contenido: bytes) -> pd.DataFrame:
    """Lee CSV con coma o con punto y coma (exportación típica de Excel en español)."""
    texto = contenido.decode("utf-8-sig")
    cabecera = texto.splitlines()[0] if texto.strip() else ""
    separador = ";" if cabecera.count(";") > cabecera.count(",") else ","
    return pd.read_csv(BytesIO(contenido), sep=separador, encoding="utf-8-sig")


def limpiar(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df.columns = [_normalizar_nombre(columna) for columna in df.columns]
    df = df.loc[:, ~df.columns.duplicated()]

    for columna in df.columns:
        if _es_texto(df[columna]):
            df[columna] = df[columna].map(_limpiar_texto)

    df = df.dropna(how="all")
    df = df.drop_duplicates()

    for columna in df.columns:
        if "fecha" in columna:
            df[columna] = _a_fecha(df[columna])
        else:
            df[columna] = _a_numerico_si_procede(df[columna])

    return df.reset_index(drop=True)


def _es_texto(serie: pd.Series) -> bool:
    return not (
        pd.api.types.is_numeric_dtype(serie)
        or pd.api.types.is_datetime64_any_dtype(serie)
        or pd.api.types.is_bool_dtype(serie)
    )


def _normalizar_nombre(nombre) -> str:
    texto = str(nombre).strip().lower()
    texto = "".join(
        caracter
        for caracter in unicodedata.normalize("NFKD", texto)
        if not unicodedata.combining(caracter)
    )
    texto = "_".join(texto.split())
    return texto or "columna"


def _limpiar_texto(valor):
    if not isinstance(valor, str) or pd.isna(valor):
        return pd.NA
    texto = valor.strip()
    if texto.lower() in AUSENTES:
        return pd.NA
    return texto


def _a_fecha(serie: pd.Series) -> pd.Series:
    # Formatos explícitos: dayfirst se come las fechas ISO (2024-01-02 pasa a febrero).
    return pd.to_datetime(serie.map(_parse_fecha), errors="coerce")


def _parse_fecha(valor):
    if not isinstance(valor, str) or pd.isna(valor):
        return pd.NaT
    texto = valor.strip()
    for formato in FORMATOS_FECHA:
        convertido = pd.to_datetime(texto, format=formato, errors="coerce")
        if not pd.isna(convertido):
            return convertido
    return pd.NaT


def _a_numerico_si_procede(serie: pd.Series) -> pd.Series:
    if pd.api.types.is_numeric_dtype(serie):
        return serie
    convertido = pd.to_numeric(serie, errors="coerce")
    originales = int(serie.notna().sum())
    if originales == 0:
        return serie
    if convertido.notna().sum() / originales >= UMBRAL_NUMERICO:
        return convertido
    return serie


if __name__ == "__main__":
    from pathlib import Path

    ruta = Path(__file__).resolve().parents[1] / "datos" / "ventas_sucio.csv"
    entrada = leer_csv(ruta.read_bytes())
    salida = limpiar(entrada)
    print(f"Filas de entrada: {len(entrada)}")
    print(entrada.to_string(index=False))
    print(f"\nFilas de salida: {len(salida)}")
    print(salida.to_string(index=False))
    print("\nTipos:")
    print(salida.dtypes.to_string())

# Importación de centros de costo

Convierte un CSV de centros de costo en **SQL idempotente** para una empresa.
No necesita dependencias ni conexión a la base: el archivo generado se ejecuta
en Supabase con `service_role`.

El objetivo es cargar la jerarquía real sin hardcodear códigos ni depender de
una herramienta externa, y poder repetir la importación sin duplicar filas.

## Uso

```bash
node tools/importar-ceco/index.mjs \
  --empresa EMPRESA-A \
  --archivo tools/importar-ceco/ejemplo/centros-ejemplo.csv \
  --salida tools/importar-ceco/datos/importar-centros.sql
```

Sin `--salida`, el SQL se escribe en stdout y los mensajes en stderr.

| Opción | Descripción |
|---|---|
| `--empresa` | Código de la empresa destino (obligatorio). |
| `--archivo` | CSV de entrada (obligatorio). |
| `--salida` | Archivo SQL de salida (opcional). |
| `--help` | Muestra la ayuda. |

## Formato del CSV

```csv
codigo,nombre,padre
100,Parque Central,
110,Operaciones,100
111,Atracciones,110
```

- `codigo` y `nombre` son obligatorios; `padre` es opcional.
- La primera fila debe ser el encabezado. Se aceptan alias como `Código`,
  `Nombre del centro`, `CECO`, `parent` o `ceco_padre`.
- Se admite coma, punto y coma o tabulador como delimitador.
- Se admiten campos entre comillas, comas dentro de comillas, comillas
  escapadas (`""`), saltos de línea dentro de un campo, BOM de Excel y CRLF.
- Las líneas vacías y las que empiezan con `#` se ignoran.

## Normalización

El código canónico se pasa a mayúsculas y se le quitan espacios, puntos,
guiones, barras y guiones bajos:

| Entrada | Código canónico |
|---|---|
| `057.01` | `05701` |
| `057-01` | `05701` |
| `abc 12/3` | `ABC123` |

Los ceros a la izquierda se conservan. El nombre se recorta y se colapsan los
espacios internos; el máximo es de 160 caracteres.

## Validaciones

Antes de generar SQL, el plan rechaza:

- códigos vacíos, no textuales, con caracteres inválidos o de más de 32 caracteres;
- nombres vacíos o de más de 160 caracteres;
- códigos duplicados en el archivo (aunque cambie el formato);
- un centro que se declara padre de sí mismo;
- ciclos en la jerarquía.

Si un padre no viene en el CSV, se emite una **advertencia** y el SQL comprueba
antes de enlazar que ese padre ya exista en la base. Si falta, la transacción se
aborta completa: no queda una jerarquía a medias.

## SQL generado

1. Verifica que la empresa exista por `codigo`.
2. Da de alta o renombra los centros con
   `insert ... on conflict (empresa_id, codigo) do update`.
3. Comprueba que todos los padres existan en la empresa.
4. Enlaza cada centro con su padre (dispara la propagación de `ruta`).
5. Deja como raíz los centros sin padre declarado.

Todo ocurre en una transacción `begin`/`commit`, por lo que repetir el archivo
deja el mismo resultado y no duplica filas.

El SQL se debe ejecutar con `service_role` porque crear raíces y mover centros
de costo están reservados a ese rol por RLS y por los grants de columna.

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f datos/importar-centros.sql
```

## Datos reales

Los CSV reales y el SQL generado **no se versionan**: `datos/`, `salida/` y
`*.local.csv` están en `.gitignore`. Solo se versiona `ejemplo/`, con datos
ficticios para probar la herramienta.

## Pruebas

```bash
pnpm --dir tools/importar-ceco test
```

La suite cubre normalización, parser CSV, duplicados, ciclos, padres faltantes,
escape de comillas y el contrato del SQL idempotente.

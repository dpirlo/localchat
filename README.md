# IA Local

Chat local con Ollama, búsqueda web mediante DuckDuckGo, historial, imágenes y lectura de texto de archivos PDF.

Para buscar una imagen adjunta en Google Lens, Yandex, TinEye y Ascii2D, la aplicación necesita darle una URL pública temporal. Usa Uguu durante 3 horas y recurre a Litterbox durante 1 hora si el primer servicio falla. No adjuntes imágenes privadas o sensibles a la búsqueda inversa.

## Instalar

Los instaladores descargan una versión LTS de Node.js dentro de `.runtime` —sin modificar la instalación global—, ejecutan `npm ci`, instalan Ollama desde su fuente oficial, descargan los modelos de `models.txt` y crean el acceso de la aplicación.

### Windows

Ejecutá `instalar-windows.bat`. Crea accesos directos en el Escritorio y el menú Inicio, y luego abre la aplicación. Ollama queda fuera del inicio automático de Windows: IA Local lo inicia y lo cierra cuando corresponde.

### macOS

Desde Terminal, dentro de esta carpeta, ejecutá:

```bash
bash instalar-mac-linux.sh
```

El instalador es compatible con Apple Silicon y Mac Intel, crea **IA Local.app** en `~/Applications` y la abre al terminar. Podés arrastrarla al Dock; el código continúa en esta carpeta para que siga siendo editable.

### Linux

Ejecutá el mismo comando:

```bash
bash instalar-mac-linux.sh
```

Instala el acceso **IA Local** en el menú de aplicaciones. Si Ollama creó un servicio de `systemd`, el instalador lo desactiva para que el modelo sólo quede activo mientras se usa el chat.

La descarga inicial incluye `qwen3:8b` para texto y `qwen2.5vl:3b` para imágenes. La lista se puede editar en `models.txt`. Para reinstalar sin bajar modelos usá `-SkipModels` en Windows o `--skip-models` en macOS/Linux. También existen `-NoLaunch`/`--no-launch` y `-ForceRuntime`/`--force-runtime`.

## Abrir

En Windows ejecutá **IA Local.exe**; en macOS abrí **IA Local.app**; en Linux usá el acceso del menú. Los lanzadores son pequeños: la aplicación sigue definida por los archivos editables de esta carpeta.

## Archivos principales

- `index.html`: interfaz, estilos, Markdown e historial.
- `server.js`: servidor Node, búsqueda web y conexión con Ollama.
- `package.json`: dependencia local usada para extraer texto de PDFs.
- `iniciar-chat.ps1`: arranque y cierre automático de Node/Ollama.
- `iniciar-chat.sh`: arranque y cierre automático en macOS/Linux.
- `iniciar-chat.vbs`: ejecuta PowerShell oculto.
- `instalar-windows.bat`: instalador completo de Windows.
- `instalar-mac-linux.sh`: instalador de macOS/Linux.
- `models.txt`: modelos que descargan los instaladores.
- `IA Local.exe`: lanzador para anclar al Inicio o a la barra de tareas.
- `src/IALocalLauncher.cs`: código fuente del lanzador.

El historial completo se guarda localmente en IndexedDB dentro del perfil de Chrome, sin límites artificiales de conversaciones, mensajes o longitud. Al actualizar desde una versión anterior, el historial existente en `localStorage` se migra automáticamente y se conserva como respaldo. Las imágenes y el contenido completo de los PDFs no se guardan en el historial.

Para no sobrecargar a Ollama, cada consulta envía únicamente el tramo reciente y los pares de mensajes anteriores más relacionados con la pregunta actual. Este recorte afecta sólo al contexto temporal del modelo, nunca al historial almacenado.

El selector **Profundidad** permite elegir entre **Rápido** (respuesta breve y poco historial), **Normal** (equilibrado) y **Pensar** (más contexto y mayor presupuesto de generación). La preferencia queda guardada en el navegador.

Las respuestas que usan búsqueda web muestran las fuentes reales en tarjetas enlazadas. Cada tarjeta indica qué frases fueron respaldadas por su resultado cuando el modelo incluye las referencias `[1]`, `[2]`, etc. El botón **Buscar otras fuentes** repite la consulta excluyendo los dominios anteriores.

El menú de conversaciones incluye una búsqueda global por palabras. Los resultados muestran el fragmento coincidente y abren la conversación directamente en el mensaje encontrado.

Desde ese mismo menú se puede exportar todo el historial como JSON reimportable o como Markdown legible. La importación combina el archivo con el historial existente: agrega conversaciones nuevas y sólo reemplaza una coincidencia cuando la copia importada es más reciente.

Cada respuesta guarda su tiempo total y, cuando Ollama informa los datos, ofrece un panel desplegable con modelo, CPU/GPU, tokens de entrada y salida, velocidad, contexto y memoria ocupada. Estas métricas se conservan como metadatos del historial y no se envían a Ollama como parte del contexto.

Al abrir IA Local, el lanzador aplica la preferencia de GPU de alto rendimiento a Ollama, activa temporalmente el plan energético de alto rendimiento y asigna prioridad `AboveNormal` al proceso de inferencia. Al cerrar la ventana, restaura el plan energético que estaba activo antes de abrirla.

## Configuración local opcional

Copiá `config.example.json` como `config.local.json` para agregar instrucciones personales al modelo sin publicarlas en Git. Los archivos `*.local.json` están ignorados por el repositorio.

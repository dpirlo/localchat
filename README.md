# IA Local

Chat local con Ollama, búsqueda web mediante DuckDuckGo, historial, imágenes y lectura de texto de archivos PDF.

## Abrir

Ejecutá **IA Local.exe**. El ejecutable es sólo un lanzador pequeño: la aplicación sigue definida por los archivos editables de esta carpeta.

La primera vez, ejecutá `npm install` dentro de esta carpeta para instalar el lector local de PDF.

## Archivos principales

- `index.html`: interfaz, estilos, Markdown e historial.
- `server.js`: servidor Node, búsqueda web y conexión con Ollama.
- `package.json`: dependencia local usada para extraer texto de PDFs.
- `iniciar-chat.ps1`: arranque y cierre automático de Node/Ollama.
- `iniciar-chat.vbs`: ejecuta PowerShell oculto.
- `IA Local.exe`: lanzador para anclar al Inicio o a la barra de tareas.
- `src/IALocalLauncher.cs`: código fuente del lanzador.

El historial completo se guarda localmente en IndexedDB dentro del perfil de Chrome, sin límites artificiales de conversaciones, mensajes o longitud. Al actualizar desde una versión anterior, el historial existente en `localStorage` se migra automáticamente y se conserva como respaldo. Las imágenes y el contenido completo de los PDFs no se guardan en el historial.

Para no sobrecargar a Ollama, cada consulta envía únicamente el tramo reciente y los pares de mensajes anteriores más relacionados con la pregunta actual. Este recorte afecta sólo al contexto temporal del modelo, nunca al historial almacenado.

El menú de conversaciones incluye una búsqueda global por palabras. Los resultados muestran el fragmento coincidente y abren la conversación directamente en el mensaje encontrado.

Desde ese mismo menú se puede exportar todo el historial como JSON reimportable o como Markdown legible. La importación combina el archivo con el historial existente: agrega conversaciones nuevas y sólo reemplaza una coincidencia cuando la copia importada es más reciente.

Cada respuesta guarda su tiempo total y, cuando Ollama informa los datos, ofrece un panel desplegable con modelo, CPU/GPU, tokens de entrada y salida, velocidad, contexto y memoria ocupada. Estas métricas se conservan como metadatos del historial y no se envían a Ollama como parte del contexto.

Al abrir IA Local, el lanzador aplica la preferencia de GPU de alto rendimiento a Ollama, activa temporalmente el plan energético de alto rendimiento y asigna prioridad `AboveNormal` al proceso de inferencia. Al cerrar la ventana, restaura el plan energético que estaba activo antes de abrirla.

## Configuración local opcional

Copiá `config.example.json` como `config.local.json` para agregar instrucciones personales al modelo sin publicarlas en Git. Los archivos `*.local.json` están ignorados por el repositorio.

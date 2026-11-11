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

El historial se guarda localmente en el perfil de Chrome. Las imágenes y el contenido completo de los PDFs no se guardan en el historial.

Cada respuesta guarda y muestra su tiempo total de trabajo. Ese dato se conserva como metadato del historial y no se envía a Ollama como parte del contexto.

Al abrir IA Local, el lanzador aplica la preferencia de GPU de alto rendimiento a Ollama, activa temporalmente el plan energético de alto rendimiento y asigna prioridad `AboveNormal` al proceso de inferencia. Al cerrar la ventana, restaura el plan energético que estaba activo antes de abrirla.

## Configuración local opcional

Copiá `config.example.json` como `config.local.json` para agregar instrucciones personales al modelo sin publicarlas en Git. Los archivos `*.local.json` están ignorados por el repositorio.

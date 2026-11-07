# IA Local

Chat local con Ollama, búsqueda web mediante DuckDuckGo, historial y soporte de imágenes.

## Abrir

Ejecutá **IA Local.exe**. El ejecutable es sólo un lanzador pequeño: la aplicación sigue definida por los archivos editables de esta carpeta.

## Archivos principales

- `index.html`: interfaz, estilos, Markdown e historial.
- `server.js`: servidor Node, búsqueda web y conexión con Ollama.
- `iniciar-chat.ps1`: arranque y cierre automático de Node/Ollama.
- `iniciar-chat.vbs`: ejecuta PowerShell oculto.
- `IA Local.exe`: lanzador para anclar al Inicio o a la barra de tareas.
- `src/IALocalLauncher.cs`: código fuente del lanzador.

El historial se guarda localmente en el perfil de Chrome. Las imágenes no se guardan en el historial.

## Configuración local opcional

Copiá `config.example.json` como `config.local.json` para agregar instrucciones personales al modelo sin publicarlas en Git. Los archivos `*.local.json` están ignorados por el repositorio.

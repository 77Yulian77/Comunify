# Cómo subir los cambios (GitHub → Netlify, y Supabase)

## Orden recomendado
1. **Supabase primero** (la base), 2. **GitHub** (el código; Netlify despliega solo).
Si subes el código antes que el SQL, el panel mostrará error de columnas hasta que ejecutes el SQL.

## 1. Supabase (SQL)
1. Entra a https://supabase.com/dashboard y abre el proyecto de Comunify.
2. Menú izquierdo → **SQL Editor** → **New query**.
3. Abre `supabase/EJECUTAR_EN_SUPABASE.sql`, copia TODO, pégalo y pulsa **Run**.
   Debe decir "Success. No rows returned". Se puede ejecutar más de una vez sin problema.
4. (Opcional) Verifica en **Table Editor → incidencias** que existen las columnas
   `resolucion_comentario`, `resolucion_foto_url` y `resuelta_at`.

## 2. Cuenta de Monteclaro
Authentication → Users → Add user → Create new user (marca *Auto Confirm User*). Ver `CREAR_ADMIN_MONTECLARO.md`.

## 3. GitHub
### Opción A: desde la página web (sin instalar nada)
1. Abre tu repositorio en github.com.
2. Para cada archivo cambiado: entra a su carpeta → **Add file → Upload files** y arrastra el archivo
   (respeta la carpeta: `project/dashboard.html`, `project/consultar.html`, `project/js/api.js`, `project/js/auth.js`,
   `supabase/migrations/…`, `supabase/scripts/…`, `docs/…`). Si el archivo ya existe, lo reemplaza.
3. Escribe un mensaje (ej. "Eliminar definitivo, resolución con foto, logout a login") y pulsa **Commit changes**
   en la rama `main`.

### Opción B: con Git (terminal)
```bash
git pull                      # trae lo último
# copia aquí los archivos del zip sobre el proyecto
git status                    # revisa qué cambió
git add -A
git commit -m "Eliminar definitivo, resolución con foto/comentario, logout a login"
git push
```

## 4. Netlify
Al hacer push a `main`, Netlify construye y publica solo (1–2 min). Revisa en Netlify → Deploys que diga **Published**.
Tras el deploy, recarga con Ctrl+F5 y vuelve a iniciar sesión como administrador.

## 5. Prueba rápida
1. Panel → un ticket → **Estado** → Resuelto → debe pedir comentario y foto.
2. `consultar.html?ticket=TCK-…` → debe verse la sección **Solución** con comentario y foto.
3. **Archivar** ese ticket y volver a consultarlo: la solución sigue ahí.
4. **Eliminar** un ticket de prueba → desaparece y su foto se borra.
5. Cerrar sesión → debe llevar a `login.html`.

> No subas el archivo `.env` con las llaves a GitHub si el repositorio es público.

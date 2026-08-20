# Setup sin credenciales

## Requisitos
- Proyecto nuevo y aislado en Supabase.
- Antigravity CLI.
- Supabase MCP.
- Datos exclusivamente ficticios.

## Configuración MCP
Usar el archivo de ejemplo `config/mcp_config.example.json`.

Nunca publicar:
- tokens
- contraseñas
- claves API
- secretos OAuth
- archivos `.env`

La configuración real local puede vivir en `.agents/mcp_config.json`, pero `.agents/` debe quedar ignorado por Git.

## Migración
La estructura se creó mediante:
`supabase/migrations/20260820000000_inicializar_esquema_clinica_vitalis.sql`

La migración fue revisada antes de aplicarse por MCP.

## Seed
Los datos ficticios están en:
`supabase/seed.sql`

El seed reconstruye el escenario de prueba y usa una limpieza controlada inicial; no debe usarse de esa forma en producción.

## Read-only
La segunda conexión añade:
`read_only=true`

Sirve para permitir consultas y bloquear escrituras a nivel de PostgreSQL.

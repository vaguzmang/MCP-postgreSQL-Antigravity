# Seguridad

## Mínimo privilegio
`supabase-vitalis` permite lectura/escritura.
`supabase-vitalis-ro` permite lectura y bloquea escrituras.

La prueba mostró que la seguridad no depende solo de instrucciones al modelo: PostgreSQL rechazó la operación.

## Integridad vs confidencialidad
`read_only` protege principalmente integridad.
No garantiza confidencialidad porque `SELECT` sigue disponible.

## Prompt injection
El texto malicioso almacenado fue tratado como dato y no como instrucción.

Riesgo residual: el texto fue reproducido literalmente. Si esa salida alimentara otro agente o workflow, podría reabrirse el riesgo.

## RLS
Supabase reportó RLS deshabilitado durante el piloto.
Para producción deben añadirse:
- autenticación
- roles
- RLS
- vistas/RPC controladas
- permisos mínimos
- confirmaciones para acciones sensibles

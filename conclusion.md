# Conclusión final

El agente demostró capacidad para consultar disponibilidad, agendar y reprogramar manteniendo consistencia gracias a restricciones y triggers de PostgreSQL.

La prueba de prompt injection indirecto fue superada en el escenario evaluado: el contenido malicioso fue tratado como dato. Sin embargo, fue reproducido literalmente, por lo que el riesgo no desaparece en cadenas con otros agentes.

El modo `read_only` mostró el valor del mínimo privilegio: las lecturas funcionaron, mientras que `UPDATE` e `INSERT` fueron bloqueados por PostgreSQL con error 25006.

También se observó una limitación funcional: el agente llegó a elegir una alternativa horaria distinta sin pedir confirmación explícita.

Por ello, el asistente no debería entregarse todavía directamente a recepcionistas con acceso técnico amplio a Supabase. En producción debería operar detrás de una aplicación con autenticación, roles, RLS, funciones controladas y confirmaciones obligatorias. En su estado actual es adecuado como herramienta técnica interna, piloto supervisado o demostrador académico.

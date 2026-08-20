# Reproducibilidad

Se eligieron migraciones formales en lugar de cambios ad-hoc.

Razones:
- trazabilidad
- versionado
- repetibilidad
- revisión previa
- auditoría
- compatibilidad con Git

Flujo seguido:
```text
agente propone
↓
archivo local
↓
revisión
↓
autorización humana
↓
apply_migration
↓
verificación
```

La migración contiene estructura.
El `seed.sql` contiene únicamente datos ficticios.

El seed usa `TRUNCATE ... CASCADE` para reconstruir el escenario, apropiado solo para este piloto aislado.

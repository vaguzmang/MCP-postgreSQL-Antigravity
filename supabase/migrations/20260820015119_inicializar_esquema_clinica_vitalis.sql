-- ============================================================================
-- Migración: 20260820000000_inicializar_esquema_clinica_vitalis.sql
-- Propósito: Crear el esquema relacional de Clínica Vitalis (Bucaramanga, Colombia)
-- Entidades: especialidades, medicos, pacientes, bloques_disponibilidad, citas
-- Garantías:
--   1. Integridad referencial en cascada/restringida según reglas de negocio.
--   2. Verificación de rangos de fechas (fecha_fin > fecha_inicio).
--   3. Prevención de solapamiento de horarios por médico (btree_gist exclusion).
--   4. Prevención estructural de doble reserva (índice único parcial).
--   5. Sincronización automática del estado del bloque con el ciclo de vida de la cita (Triggers).
-- ============================================================================

-- Habilitar extensión btree_gist para restricciones de exclusión con campos escalares y rangos
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- 1. Catálogo de Especialidades
CREATE TABLE IF NOT EXISTS especialidades (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre TEXT NOT NULL UNIQUE,
    descripcion TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Médicos de la Clínica
CREATE TABLE IF NOT EXISTS medicos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    especialidad_id UUID NOT NULL REFERENCES especialidades(id) ON DELETE RESTRICT,
    nombre TEXT NOT NULL,
    correo TEXT UNIQUE,
    telefono TEXT,
    activo BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Pacientes (Permite registro ágil con solo nombre durante el piloto)
CREATE TABLE IF NOT EXISTS pacientes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre TEXT NOT NULL,
    telefono TEXT,
    correo TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. Bloques de Disponibilidad Horaria por Médico
CREATE TABLE IF NOT EXISTS bloques_disponibilidad (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    medico_id UUID NOT NULL REFERENCES medicos(id) ON DELETE RESTRICT,
    fecha_inicio TIMESTAMPTZ NOT NULL,
    fecha_fin TIMESTAMPTZ NOT NULL,
    estado TEXT NOT NULL DEFAULT 'disponible',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Validaciones de integridad
    CONSTRAINT chk_bloque_fechas_validas CHECK (fecha_fin > fecha_inicio),
    CONSTRAINT chk_bloque_estado_valido CHECK (estado IN ('disponible', 'reservado', 'cancelado')),
    
    -- Impide que un mismo médico tenga bloques solapados en el tiempo (excepto bloques cancelados)
    CONSTRAINT no_solapamiento_bloques_medico EXCLUDE USING gist (
        medico_id WITH =,
        tstzrange(fecha_inicio, fecha_fin) WITH &&
    ) WHERE (estado != 'cancelado')
);

-- 5. Citas Médicas (El médico se deriva a través del bloque_id)
CREATE TABLE IF NOT EXISTS citas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bloque_id UUID NOT NULL REFERENCES bloques_disponibilidad(id) ON DELETE RESTRICT,
    paciente_id UUID NOT NULL REFERENCES pacientes(id) ON DELETE RESTRICT,
    estado TEXT NOT NULL DEFAULT 'programada',
    motivo_consulta TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Validaciones de integridad
    CONSTRAINT chk_cita_estado_valido CHECK (estado IN ('programada', 'confirmada', 'completada', 'cancelada'))
);

-- 6. Prevención de doble reserva: Un mismo bloque solo puede tener UNA cita activa a la vez
CREATE UNIQUE INDEX IF NOT EXISTS idx_citas_bloque_activo_unico
ON citas (bloque_id)
WHERE estado != 'cancelada';

-- 7. Índices de optimización para consultas frecuentes del agente
CREATE INDEX IF NOT EXISTS idx_medicos_especialidad ON medicos(especialidad_id) WHERE activo = true;
CREATE INDEX IF NOT EXISTS idx_bloques_medico_fecha ON bloques_disponibilidad(medico_id, fecha_inicio);
CREATE INDEX IF NOT EXISTS idx_bloques_disponibles ON bloques_disponibilidad(fecha_inicio) WHERE estado = 'disponible';
CREATE INDEX IF NOT EXISTS idx_citas_paciente ON citas(paciente_id);

-- 8. Función y Trigger para sincronización automática del estado del bloque de disponibilidad
CREATE OR REPLACE FUNCTION fn_sincronizar_estado_bloque_cita()
RETURNS TRIGGER AS $$
BEGIN
    -- Caso A: Inserción de una nueva cita
    IF (TG_OP = 'INSERT') THEN
        IF (NEW.estado != 'cancelada') THEN
            -- Validar que el bloque esté disponible
            IF NOT EXISTS (
                SELECT 1 FROM bloques_disponibilidad 
                WHERE id = NEW.bloque_id AND estado = 'disponible'
            ) THEN
                RAISE EXCEPTION 'El bloque de disponibilidad (%) no se encuentra disponible para reserva.', NEW.bloque_id;
            END IF;
            
            -- Marcar bloque como reservado
            UPDATE bloques_disponibilidad
            SET estado = 'reservado'
            WHERE id = NEW.bloque_id;
        END IF;
        RETURN NEW;

    -- Caso B: Actualización de una cita existente
    ELSIF (TG_OP = 'UPDATE') THEN
        -- B1: Reprogramación / Traslado a otro bloque
        IF (OLD.bloque_id IS DISTINCT FROM NEW.bloque_id) THEN
            -- Liberar bloque anterior
            UPDATE bloques_disponibilidad
            SET estado = 'disponible'
            WHERE id = OLD.bloque_id;

            -- Reservar nuevo bloque si la cita sigue activa
            IF (NEW.estado != 'cancelada') THEN
                IF NOT EXISTS (
                    SELECT 1 FROM bloques_disponibilidad 
                    WHERE id = NEW.bloque_id AND estado = 'disponible'
                ) THEN
                    RAISE EXCEPTION 'El nuevo bloque de disponibilidad (%) no se encuentra disponible.', NEW.bloque_id;
                END IF;

                UPDATE bloques_disponibilidad
                SET estado = 'reservado'
                WHERE id = NEW.bloque_id;
            END IF;

        -- B2: Mismo bloque, pero cambio de estado de la cita
        ELSIF (OLD.estado IS DISTINCT FROM NEW.estado) THEN
            -- Cancelación de cita: libera el bloque
            IF (NEW.estado = 'cancelada' AND OLD.estado != 'cancelada') THEN
                UPDATE bloques_disponibilidad
                SET estado = 'disponible'
                WHERE id = NEW.bloque_id;
            -- Reactivación de cita cancelada: vuelve a reservar el bloque
            ELSIF (OLD.estado = 'cancelada' AND NEW.estado != 'cancelada') THEN
                IF NOT EXISTS (
                    SELECT 1 FROM bloques_disponibilidad 
                    WHERE id = NEW.bloque_id AND estado = 'disponible'
                ) THEN
                    RAISE EXCEPTION 'El bloque de disponibilidad (%) no está disponible para reactivar la cita.', NEW.bloque_id;
                END IF;

                UPDATE bloques_disponibilidad
                SET estado = 'reservado'
                WHERE id = NEW.bloque_id;
            END IF;
        END IF;
        RETURN NEW;

    -- Caso C: Eliminación física de una cita (por seguridad)
    ELSIF (TG_OP = 'DELETE') THEN
        IF (OLD.estado != 'cancelada') THEN
            UPDATE bloques_disponibilidad
            SET estado = 'disponible'
            WHERE id = OLD.bloque_id;
        END IF;
        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Crear el trigger sobre la tabla citas
DROP TRIGGER IF EXISTS trg_sincronizar_estado_bloque_cita ON citas;
CREATE TRIGGER trg_sincronizar_estado_bloque_cita
BEFORE INSERT OR UPDATE OR DELETE ON citas
FOR EACH ROW
EXECUTE FUNCTION fn_sincronizar_estado_bloque_cita();

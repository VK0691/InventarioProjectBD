-- Configurar esquema (equivalente a ALTER SESSION en PostgreSQL)
SET search_path TO GITT_INV;

-- A. Encabezado del proyecto cargado.
-- B-F. Limpieza, tablas, restricciones, indices, comentarios y triggers.

-- Eliminar triggers
DROP TRIGGER IF EXISTS trg_prestamo_devolucion ON prestamo;
DROP TRIGGER IF EXISTS trg_detalle_prestamo_validar ON detalle_prestamo;
DROP TRIGGER IF EXISTS trg_detalle_prestamo_estado ON detalle_prestamo;
DROP TRIGGER IF EXISTS trg_articulo_auditoria ON articulo;

-- Eliminar tablas en orden inverso
DROP TABLE IF EXISTS auditoria CASCADE;
DROP TABLE IF EXISTS notificacion CASCADE;
DROP TABLE IF EXISTS movimiento CASCADE;
DROP TABLE IF EXISTS mantenimiento CASCADE;
DROP TABLE IF EXISTS detalle_prestamo CASCADE;
DROP TABLE IF EXISTS imagen_articulo CASCADE;
DROP TABLE IF EXISTS prestamo CASCADE;
DROP TABLE IF EXISTS articulo CASCADE;
DROP TABLE IF EXISTS categoria CASCADE;
DROP TABLE IF EXISTS ubicacion CASCADE;
DROP TABLE IF EXISTS departamento CASCADE;
DROP TABLE IF EXISTS usuario CASCADE;
DROP TABLE IF EXISTS rol CASCADE;

-- Crear tablas
CREATE TABLE rol (
    id_rol SERIAL PRIMARY KEY,
    nombre_rol VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE usuario (
    id_usuario SERIAL PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL,
    correo VARCHAR(150) NOT NULL UNIQUE,
    contrasena VARCHAR(255) NOT NULL,
    id_rol INTEGER NOT NULL REFERENCES rol(id_rol),
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE departamento (
    id_departamento SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE ubicacion (
    id_ubicacion SERIAL PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL,
    id_departamento INTEGER NOT NULL REFERENCES departamento(id_departamento)
);

CREATE TABLE categoria (
    id_categoria SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE articulo (
    id_articulo SERIAL PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL,
    estado VARCHAR(20) DEFAULT 'DISPONIBLE' NOT NULL,
    codigo VARCHAR(50) NOT NULL UNIQUE,
    id_categoria INTEGER NOT NULL REFERENCES categoria(id_categoria),
    id_ubicacion INTEGER NOT NULL REFERENCES ubicacion(id_ubicacion),
    id_responsable INTEGER NULL REFERENCES usuario(id_usuario) ON DELETE SET NULL,
    valor_estimado NUMERIC(10,2) DEFAULT 0 NOT NULL,
    descripcion VARCHAR(500),
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fecha_actualizacion TIMESTAMP,
    CONSTRAINT ck_articulo_estado CHECK (estado IN ('DISPONIBLE','PRESTADO','MANTENIMIENTO','BAJA'))
);

CREATE TABLE imagen_articulo (
    id_imagen SERIAL PRIMARY KEY,
    id_articulo INTEGER NOT NULL REFERENCES articulo(id_articulo) ON DELETE CASCADE,
    url_imagen VARCHAR(500) NOT NULL,
    descripcion VARCHAR(250),
    es_principal CHAR(1) DEFAULT 'S' NOT NULL,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_imagen_articulo_principal CHECK (es_principal IN ('S','N'))
);

CREATE TABLE prestamo (
    id_prestamo SERIAL PRIMARY KEY,
    fecha_prestamo TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fecha_devolucion TIMESTAMP NOT NULL,
    id_usuario INTEGER NOT NULL REFERENCES usuario(id_usuario),
    estado VARCHAR(20) DEFAULT 'ACTIVO' NOT NULL,
    observacion VARCHAR(500),
    CONSTRAINT ck_prestamo_estado CHECK (estado IN ('ACTIVO','DEVUELTO','VENCIDO'))
);

CREATE TABLE detalle_prestamo (
    id_detalle SERIAL PRIMARY KEY,
    id_prestamo INTEGER NOT NULL REFERENCES prestamo(id_prestamo) ON DELETE CASCADE,
    id_articulo INTEGER NOT NULL REFERENCES articulo(id_articulo),
    UNIQUE(id_prestamo, id_articulo)
);

CREATE TABLE mantenimiento (
    id_mantenimiento SERIAL PRIMARY KEY,
    tipo VARCHAR(20) NOT NULL,
    fecha TIMESTAMP NOT NULL,
    id_articulo INTEGER NOT NULL REFERENCES articulo(id_articulo),
    estado VARCHAR(20) DEFAULT 'PENDIENTE' NOT NULL,
    observacion VARCHAR(500),
    CONSTRAINT ck_mantenimiento_tipo CHECK (tipo IN ('PREVENTIVO','CORRECTIVO')),
    CONSTRAINT ck_mantenimiento_estado CHECK (estado IN ('PENDIENTE','EN_PROCESO','FINALIZADO'))
);

CREATE TABLE movimiento (
    id_movimiento SERIAL PRIMARY KEY,
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    tipo VARCHAR(20) NOT NULL,
    id_articulo INTEGER NOT NULL REFERENCES articulo(id_articulo),
    observacion VARCHAR(500),
    CONSTRAINT ck_movimiento_tipo CHECK (tipo IN ('INGRESO','TRASLADO','PRESTAMO','DEVOLUCION','MANTENIMIENTO'))
);

CREATE TABLE notificacion (
    id_notificacion SERIAL PRIMARY KEY,
    mensaje VARCHAR(500) NOT NULL,
    estado VARCHAR(20) DEFAULT 'PENDIENTE' NOT NULL,
    id_prestamo INTEGER NOT NULL REFERENCES prestamo(id_prestamo) ON DELETE CASCADE,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_notificacion_estado CHECK (estado IN ('PENDIENTE','ENVIADA','LEIDA'))
);

CREATE TABLE auditoria (
    id_auditoria SERIAL PRIMARY KEY,
    accion VARCHAR(20) NOT NULL,
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    id_usuario INTEGER NOT NULL REFERENCES usuario(id_usuario),
    tabla VARCHAR(50),
    descripcion VARCHAR(500),
    CONSTRAINT ck_auditoria_accion CHECK (accion IN ('INSERT','UPDATE','DELETE','LOGIN','PRESTAMO','DEVOLUCION'))
);

-- Crear índices
CREATE INDEX ix_articulo_estado ON articulo(estado);
CREATE INDEX ix_prestamo_fecha_prestamo ON prestamo(fecha_prestamo);
CREATE INDEX ix_prestamo_fecha_devolucion ON prestamo(fecha_devolucion);
CREATE INDEX ix_mantenimiento_fecha ON mantenimiento(fecha);
CREATE INDEX ix_ubicacion_departamento ON ubicacion(id_departamento);
CREATE INDEX ix_articulo_categoria ON articulo(id_categoria);
CREATE INDEX ix_articulo_ubicacion ON articulo(id_ubicacion);
CREATE INDEX ix_imagen_articulo ON imagen_articulo(id_articulo);

-- Comentarios
COMMENT ON TABLE rol IS 'Catalogo de roles de usuario del sistema.';
COMMENT ON TABLE usuario IS 'Usuarios autenticados y responsables de prestamos o auditoria.';
COMMENT ON TABLE departamento IS 'Departamentos de la FISEI.';
COMMENT ON TABLE ubicacion IS 'Ubicaciones fisicas pertenecientes a departamentos.';
COMMENT ON TABLE categoria IS 'Categorias de articulos tecnologicos.';
COMMENT ON TABLE articulo IS 'Inventario tecnologico administrado por la FISEI.';
COMMENT ON TABLE imagen_articulo IS 'Imagenes o evidencias visuales asociadas a articulos.';
COMMENT ON TABLE prestamo IS 'Cabecera de prestamos de articulos.';
COMMENT ON TABLE detalle_prestamo IS 'Articulos incluidos en cada prestamo.';
COMMENT ON TABLE mantenimiento IS 'Historial y programacion de mantenimientos.';
COMMENT ON TABLE movimiento IS 'Movimientos operativos de articulos.';
COMMENT ON TABLE notificacion IS 'Notificaciones asociadas a prestamos.';
COMMENT ON TABLE auditoria IS 'Registro de acciones criticas del sistema.';

-- Triggers

-- Trigger de auditoría para artículos
CREATE OR REPLACE FUNCTION trg_articulo_auditoria_func()
RETURNS TRIGGER AS $$
DECLARE
    v_usuario INTEGER;
    v_accion VARCHAR(20);
    v_codigo VARCHAR(50);
BEGIN
    IF (TG_OP = 'INSERT') THEN
        v_accion := 'INSERT';
        v_usuario := COALESCE(NEW.id_responsable, 1);
        v_codigo := NEW.codigo;
    ELSIF (TG_OP = 'UPDATE') THEN
        v_accion := 'UPDATE';
        v_usuario := COALESCE(NEW.id_responsable, OLD.id_responsable, 1);
        v_codigo := NEW.codigo;
    ELSE
        v_accion := 'DELETE';
        v_usuario := COALESCE(OLD.id_responsable, 1);
        v_codigo := OLD.codigo;
    END IF;

    INSERT INTO auditoria (accion, fecha, id_usuario, tabla, descripcion)
    VALUES (
        v_accion,
        CURRENT_TIMESTAMP,
        v_usuario,
        'ARTICULO',
        'Auditoria automatica del articulo ' || v_codigo
    );
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_articulo_auditoria
AFTER INSERT OR UPDATE OR DELETE ON articulo
FOR EACH ROW EXECUTE FUNCTION trg_articulo_auditoria_func();

-- Trigger para actualizar estado del artículo en préstamo
CREATE OR REPLACE FUNCTION trg_detalle_prestamo_estado_func()
RETURNS TRIGGER AS $$
DECLARE
    v_estado_prestamo VARCHAR(20);
BEGIN
    SELECT estado INTO v_estado_prestamo FROM prestamo WHERE id_prestamo = NEW.id_prestamo;
    IF v_estado_prestamo = 'ACTIVO' THEN
        UPDATE articulo SET estado = 'PRESTADO', fecha_actualizacion = CURRENT_TIMESTAMP 
        WHERE id_articulo = NEW.id_articulo;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_detalle_prestamo_estado
AFTER INSERT OR UPDATE OF id_articulo ON detalle_prestamo
FOR EACH ROW EXECUTE FUNCTION trg_detalle_prestamo_estado_func();

-- Trigger para validar que un artículo no esté en préstamo activo
CREATE OR REPLACE FUNCTION trg_detalle_prestamo_validar_func()
RETURNS TRIGGER AS $$
DECLARE
    v_total INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO v_total
    FROM detalle_prestamo dp
    JOIN prestamo p ON p.id_prestamo = dp.id_prestamo
    WHERE dp.id_articulo = NEW.id_articulo
      AND p.estado = 'ACTIVO';

    IF v_total > 1 THEN
        RAISE EXCEPTION 'El artículo ya se encuentra en un préstamo activo.';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_detalle_prestamo_validar
BEFORE INSERT OR UPDATE OF id_articulo, id_prestamo ON detalle_prestamo
FOR EACH ROW EXECUTE FUNCTION trg_detalle_prestamo_validar_func();

-- Trigger para manejar devoluciones
CREATE OR REPLACE FUNCTION trg_prestamo_devolucion_func()
RETURNS TRIGGER AS $$
DECLARE
    r RECORD;
BEGIN
    IF NEW.estado = 'DEVUELTO' AND OLD.estado <> 'DEVUELTO' THEN
        FOR r IN SELECT id_articulo FROM detalle_prestamo WHERE id_prestamo = NEW.id_prestamo LOOP
            UPDATE articulo SET estado = 'DISPONIBLE', fecha_actualizacion = CURRENT_TIMESTAMP 
            WHERE id_articulo = r.id_articulo;
            
            INSERT INTO movimiento (fecha, tipo, id_articulo, observacion)
            VALUES (CURRENT_TIMESTAMP, 'DEVOLUCION', r.id_articulo, 'Devolucion registrada por trigger');
        END LOOP;

        INSERT INTO auditoria (accion, fecha, id_usuario, tabla, descripcion)
        VALUES ('DEVOLUCION', CURRENT_TIMESTAMP, NEW.id_usuario, 'PRESTAMO', 
                'Devolucion del prestamo ' || NEW.id_prestamo);
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prestamo_devolucion
AFTER UPDATE OF estado ON prestamo
FOR EACH ROW EXECUTE FUNCTION trg_prestamo_devolucion_func();

-- H. Datos de prueba
-- Reiniciar secuencias
SELECT setval('rol_id_rol_seq', 1, false);
SELECT setval('usuario_id_usuario_seq', 1, false);
SELECT setval('departamento_id_departamento_seq', 1, false);
SELECT setval('ubicacion_id_ubicacion_seq', 1, false);
SELECT setval('categoria_id_categoria_seq', 1, false);
SELECT setval('articulo_id_articulo_seq', 1, false);
SELECT setval('imagen_articulo_id_imagen_seq', 1, false);
SELECT setval('prestamo_id_prestamo_seq', 1, false);
SELECT setval('detalle_prestamo_id_detalle_seq', 1, false);
SELECT setval('mantenimiento_id_mantenimiento_seq', 1, false);
SELECT setval('movimiento_id_movimiento_seq', 1, false);
SELECT setval('notificacion_id_notificacion_seq', 1, false);
SELECT setval('auditoria_id_auditoria_seq', 1, false);

INSERT INTO rol (id_rol, nombre_rol) VALUES (1, 'Administrador');
INSERT INTO rol (id_rol, nombre_rol) VALUES (2, 'Responsable');
INSERT INTO rol (id_rol, nombre_rol) VALUES (3, 'Docente');
INSERT INTO rol (id_rol, nombre_rol) VALUES (4, 'Estudiante');

INSERT INTO usuario (id_usuario, nombre, correo, contrasena, id_rol) VALUES (1, 'Administrador FISEI', 'admin@fisei.edu.ec', 'Admin123*', 1);
INSERT INTO usuario (id_usuario, nombre, correo, contrasena, id_rol) VALUES (2, 'Responsable Laboratorio', 'responsable@fisei.edu.ec', 'Resp123*', 2);
INSERT INTO usuario (id_usuario, nombre, correo, contrasena, id_rol) VALUES (3, 'Docente Sistemas', 'docente@fisei.edu.ec', 'Docente123*', 3);
INSERT INTO usuario (id_usuario, nombre, correo, contrasena, id_rol) VALUES (4, 'Estudiante Software', 'estudiante@fisei.edu.ec', 'Estudiante123*', 4);

INSERT INTO departamento (id_departamento, nombre) VALUES (1, 'Laboratorios FISEI');
INSERT INTO departamento (id_departamento, nombre) VALUES (2, 'Aulas');
INSERT INTO departamento (id_departamento, nombre) VALUES (3, 'Administracion');

INSERT INTO ubicacion (id_ubicacion, nombre, id_departamento) VALUES (1, 'Laboratorio 1', 1);
INSERT INTO ubicacion (id_ubicacion, nombre, id_departamento) VALUES (2, 'Laboratorio 2', 1);
INSERT INTO ubicacion (id_ubicacion, nombre, id_departamento) VALUES (3, 'Aula 401', 2);
INSERT INTO ubicacion (id_ubicacion, nombre, id_departamento) VALUES (4, 'Bodega Tecnologica', 3);

INSERT INTO categoria (id_categoria, nombre) VALUES (1, 'Computadores');
INSERT INTO categoria (id_categoria, nombre) VALUES (2, 'Proyectores');
INSERT INTO categoria (id_categoria, nombre) VALUES (3, 'Redes');
INSERT INTO categoria (id_categoria, nombre) VALUES (4, 'Impresion');
INSERT INTO categoria (id_categoria, nombre) VALUES (5, 'Audio y Video');

INSERT INTO articulo (id_articulo, nombre, estado, codigo, id_categoria, id_ubicacion, id_responsable, valor_estimado, descripcion) VALUES 
(1, 'Laptop Dell Latitude', 'DISPONIBLE', 'FISEI-LAP-001', 1, 1, 2, 950.00, 'Equipo portatil para docencia.');
INSERT INTO articulo (id_articulo, nombre, estado, codigo, id_categoria, id_ubicacion, id_responsable, valor_estimado, descripcion) VALUES 
(2, 'Proyector Epson X49', 'DISPONIBLE', 'FISEI-PRO-001', 2, 3, 2, 680.00, 'Proyector para aulas.');
INSERT INTO articulo (id_articulo, nombre, estado, codigo, id_categoria, id_ubicacion, id_responsable, valor_estimado, descripcion) VALUES 
(3, 'Switch Cisco 24P', 'DISPONIBLE', 'FISEI-RED-001', 3, 2, 2, 420.00, 'Switch de laboratorio.');
INSERT INTO articulo (id_articulo, nombre, estado, codigo, id_categoria, id_ubicacion, id_responsable, valor_estimado, descripcion) VALUES 
(4, 'Impresora HP LaserJet', 'MANTENIMIENTO', 'FISEI-IMP-001', 4, 4, 2, 540.00, 'Impresora en revision.');
INSERT INTO articulo (id_articulo, nombre, estado, codigo, id_categoria, id_ubicacion, id_responsable, valor_estimado, descripcion) VALUES 
(5, 'Tablet Android', 'BAJA', 'FISEI-TAB-001', 1, 4, NULL, 300.00, 'Equipo dado de baja.');
INSERT INTO articulo (id_articulo, nombre, estado, codigo, id_categoria, id_ubicacion, id_responsable, valor_estimado, descripcion) VALUES 
(6, 'Camara Logitech', 'DISPONIBLE', 'FISEI-VID-001', 5, 1, 2, 180.00, 'Camara para videoconferencia.');

INSERT INTO imagen_articulo (id_imagen, id_articulo, url_imagen, descripcion, es_principal) VALUES 
(1, 1, 'https://images.unsplash.com/photo-1496181133206-80ce9b88a853', 'Imagen referencial de laptop', 'S');
INSERT INTO imagen_articulo (id_imagen, id_articulo, url_imagen, descripcion, es_principal) VALUES 
(2, 2, 'https://images.unsplash.com/photo-1516321318423-f06f85e504b3', 'Imagen referencial de proyector', 'S');
INSERT INTO imagen_articulo (id_imagen, id_articulo, url_imagen, descripcion, es_principal) VALUES 
(3, 3, 'https://images.unsplash.com/photo-1558494949-ef010cbdcc31', 'Imagen referencial de equipos de red', 'S');

INSERT INTO prestamo (id_prestamo, fecha_prestamo, fecha_devolucion, id_usuario, estado, observacion) VALUES 
(1, CURRENT_TIMESTAMP - INTERVAL '1 day', CURRENT_TIMESTAMP + INTERVAL '5 days', 3, 'ACTIVO', 'Prestamo para clase practica.');
INSERT INTO prestamo (id_prestamo, fecha_prestamo, fecha_devolucion, id_usuario, estado, observacion) VALUES 
(2, CURRENT_TIMESTAMP - INTERVAL '10 days', CURRENT_TIMESTAMP - INTERVAL '2 days', 4, 'DEVUELTO', 'Prestamo finalizado.');
INSERT INTO prestamo (id_prestamo, fecha_prestamo, fecha_devolucion, id_usuario, estado, observacion) VALUES 
(3, CURRENT_TIMESTAMP - INTERVAL '7 days', CURRENT_TIMESTAMP - INTERVAL '1 day', 3, 'ACTIVO', 'Prestamo vencido pendiente de devolucion.');

INSERT INTO detalle_prestamo (id_detalle, id_prestamo, id_articulo) VALUES (1, 1, 1);
INSERT INTO detalle_prestamo (id_detalle, id_prestamo, id_articulo) VALUES (2, 1, 2);
INSERT INTO detalle_prestamo (id_detalle, id_prestamo, id_articulo) VALUES (3, 2, 3);
INSERT INTO detalle_prestamo (id_detalle, id_prestamo, id_articulo) VALUES (4, 3, 6);

INSERT INTO mantenimiento (id_mantenimiento, tipo, fecha, id_articulo, estado, observacion) VALUES 
(1, 'PREVENTIVO', CURRENT_TIMESTAMP + INTERVAL '3 days', 4, 'PENDIENTE', 'Revision de toner y fusor.');
INSERT INTO mantenimiento (id_mantenimiento, tipo, fecha, id_articulo, estado, observacion) VALUES 
(2, 'CORRECTIVO', CURRENT_TIMESTAMP - INTERVAL '4 days', 3, 'FINALIZADO', 'Cambio de fuente de poder.');

INSERT INTO movimiento (id_movimiento, fecha, tipo, id_articulo, observacion) VALUES 
(1, CURRENT_TIMESTAMP - INTERVAL '30 days', 'INGRESO', 1, 'Ingreso inicial al inventario.');
INSERT INTO movimiento (id_movimiento, fecha, tipo, id_articulo, observacion) VALUES 
(2, CURRENT_TIMESTAMP - INTERVAL '29 days', 'INGRESO', 2, 'Ingreso inicial al inventario.');
INSERT INTO movimiento (id_movimiento, fecha, tipo, id_articulo, observacion) VALUES 
(3, CURRENT_TIMESTAMP - INTERVAL '1 day', 'PRESTAMO', 1, 'Prestamo registrado.');
INSERT INTO movimiento (id_movimiento, fecha, tipo, id_articulo, observacion) VALUES 
(4, CURRENT_TIMESTAMP - INTERVAL '1 day', 'PRESTAMO', 2, 'Prestamo registrado.');
INSERT INTO movimiento (id_movimiento, fecha, tipo, id_articulo, observacion) VALUES 
(5, CURRENT_TIMESTAMP - INTERVAL '4 days', 'MANTENIMIENTO', 4, 'Articulo enviado a mantenimiento.');
INSERT INTO movimiento (id_movimiento, fecha, tipo, id_articulo, observacion) VALUES 
(6, CURRENT_TIMESTAMP - INTERVAL '7 days', 'PRESTAMO', 6, 'Prestamo vencido.');

INSERT INTO notificacion (id_notificacion, mensaje, estado, id_prestamo) VALUES 
(1, 'Prestamo 1 proximo a devolucion.', 'PENDIENTE', 1);
INSERT INTO notificacion (id_notificacion, mensaje, estado, id_prestamo) VALUES 
(2, 'Prestamo 3 vencido.', 'ENVIADA', 3);
INSERT INTO notificacion (id_notificacion, mensaje, estado, id_prestamo) VALUES 
(3, 'Prestamo 2 fue devuelto.', 'LEIDA', 2);

INSERT INTO auditoria (id_auditoria, accion, fecha, id_usuario, tabla, descripcion) VALUES 
(1, 'LOGIN', CURRENT_TIMESTAMP - INTERVAL '2 days', 1, 'USUARIO', 'Ingreso administrativo.');
INSERT INTO auditoria (id_auditoria, accion, fecha, id_usuario, tabla, descripcion) VALUES 
(2, 'PRESTAMO', CURRENT_TIMESTAMP - INTERVAL '1 day', 3, 'PRESTAMO', 'Registro de prestamo 1.');
INSERT INTO auditoria (id_auditoria, accion, fecha, id_usuario, tabla, descripcion) VALUES 
(3, 'DEVOLUCION', CURRENT_TIMESTAMP - INTERVAL '2 days', 4, 'PRESTAMO', 'Devolucion del prestamo 2.');

COMMIT;

-- I. Consultas DQL
-- Q1. Listar articulos disponibles con ubicacion y responsable.
SELECT a.id_articulo, a.codigo, a.nombre, u.nombre AS ubicacion, d.nombre AS departamento, r.nombre AS responsable
FROM articulo a
JOIN ubicacion u ON u.id_ubicacion = a.id_ubicacion
JOIN departamento d ON d.id_departamento = u.id_departamento
LEFT JOIN usuario r ON r.id_usuario = a.id_responsable
WHERE a.estado = 'DISPONIBLE'
ORDER BY a.nombre;

-- Q2. Obtener total de articulos por categoria.
SELECT c.nombre AS categoria, COUNT(a.id_articulo) AS total_articulos
FROM categoria c
LEFT JOIN articulo a ON a.id_categoria = c.id_categoria
GROUP BY c.nombre
ORDER BY c.nombre;

-- Q3. Mostrar prestamos activos y fecha de devolucion.
SELECT p.id_prestamo, u.nombre AS usuario, p.fecha_prestamo, p.fecha_devolucion, p.estado
FROM prestamo p
JOIN usuario u ON u.id_usuario = p.id_usuario
WHERE p.estado = 'ACTIVO'
ORDER BY p.fecha_devolucion;

-- Q4. Mostrar articulos con mantenimiento pendiente.
SELECT a.codigo, a.nombre AS articulo, m.tipo, m.fecha, m.estado, m.observacion
FROM mantenimiento m
JOIN articulo a ON a.id_articulo = m.id_articulo
WHERE m.estado = 'PENDIENTE'
ORDER BY m.fecha;

-- Q5. Mostrar movimientos por articulo.
SELECT a.codigo, a.nombre AS articulo, mo.fecha, mo.tipo, mo.observacion
FROM movimiento mo
JOIN articulo a ON a.id_articulo = mo.id_articulo
ORDER BY a.codigo, mo.fecha DESC;

-- Q6. Mostrar notificaciones por prestamo.
SELECT p.id_prestamo, n.mensaje, n.estado, n.fecha_creacion
FROM notificacion n
JOIN prestamo p ON p.id_prestamo = n.id_prestamo
ORDER BY p.id_prestamo, n.fecha_creacion DESC;

-- Q7. Mostrar auditoria por usuario.
SELECT u.nombre AS usuario, au.accion, au.fecha, au.tabla, au.descripcion
FROM auditoria au
JOIN usuario u ON u.id_usuario = au.id_usuario
ORDER BY au.fecha DESC;

-- Q8. Mostrar articulos por departamento.
SELECT d.nombre AS departamento, a.codigo, a.nombre AS articulo, a.estado
FROM articulo a
JOIN ubicacion u ON u.id_ubicacion = a.id_ubicacion
JOIN departamento d ON d.id_departamento = u.id_departamento
ORDER BY d.nombre, a.nombre;

-- Q9. Mostrar historial completo de un prestamo.
SELECT p.id_prestamo, us.nombre AS usuario, a.codigo, a.nombre AS articulo, p.fecha_prestamo, p.fecha_devolucion, p.estado AS estado_prestamo, a.estado AS estado_articulo
FROM prestamo p
JOIN usuario us ON us.id_usuario = p.id_usuario
JOIN detalle_prestamo dp ON dp.id_prestamo = p.id_prestamo
JOIN articulo a ON a.id_articulo = dp.id_articulo
ORDER BY p.id_prestamo, a.codigo;

-- Q10. Mostrar articulos prestados actualmente.
SELECT a.codigo, a.nombre AS articulo, p.id_prestamo, u.nombre AS usuario, p.fecha_devolucion
FROM articulo a
JOIN detalle_prestamo dp ON dp.id_articulo = a.id_articulo
JOIN prestamo p ON p.id_prestamo = dp.id_prestamo
JOIN usuario u ON u.id_usuario = p.id_usuario
WHERE p.estado = 'ACTIVO'
ORDER BY p.fecha_devolucion;

-- Q11. Mostrar usuarios por rol.
SELECT r.nombre_rol, u.nombre, u.correo
FROM rol r
LEFT JOIN usuario u ON u.id_rol = r.id_rol
ORDER BY r.nombre_rol, u.nombre;

-- Q12. Mostrar prestamos vencidos.
SELECT p.id_prestamo, u.nombre AS usuario, p.fecha_prestamo, p.fecha_devolucion, p.estado
FROM prestamo p
JOIN usuario u ON u.id_usuario = p.id_usuario
WHERE p.estado = 'ACTIVO'
  AND p.fecha_devolucion < CURRENT_DATE
ORDER BY p.fecha_devolucion;

-- Q13. Calcular el valor total del inventario por departamento.
SELECT d.nombre AS departamento, COUNT(a.id_articulo) AS total_articulos, SUM(a.valor_estimado) AS valor_total
FROM departamento d
JOIN ubicacion u ON u.id_departamento = d.id_departamento
JOIN articulo a ON a.id_ubicacion = u.id_ubicacion
GROUP BY d.nombre
ORDER BY valor_total DESC;

-- Q14. Listar movimientos realizados por rango de fechas.
SELECT mo.id_movimiento, a.codigo, a.nombre AS articulo, mo.fecha, mo.tipo, mo.observacion
FROM movimiento mo
JOIN articulo a ON a.id_articulo = mo.id_articulo
WHERE mo.fecha BETWEEN CURRENT_DATE - INTERVAL '30 days' AND CURRENT_DATE + INTERVAL '1 day'
ORDER BY mo.fecha DESC, a.codigo;

-- J. Verificacion final
SELECT 'ROL' AS tabla, COUNT(*) AS total FROM rol
UNION ALL SELECT 'USUARIO', COUNT(*) FROM usuario
UNION ALL SELECT 'DEPARTAMENTO', COUNT(*) FROM departamento
UNION ALL SELECT 'UBICACION', COUNT(*) FROM ubicacion
UNION ALL SELECT 'CATEGORIA', COUNT(*) FROM categoria
UNION ALL SELECT 'ARTICULO', COUNT(*) FROM articulo
UNION ALL SELECT 'IMAGEN_ARTICULO', COUNT(*) FROM imagen_articulo
UNION ALL SELECT 'PRESTAMO', COUNT(*) FROM prestamo
UNION ALL SELECT 'DETALLE_PRESTAMO', COUNT(*) FROM detalle_prestamo
UNION ALL SELECT 'MANTENIMIENTO', COUNT(*) FROM mantenimiento
UNION ALL SELECT 'MOVIMIENTO', COUNT(*) FROM movimiento
UNION ALL SELECT 'NOTIFICACION', COUNT(*) FROM notificacion
UNION ALL SELECT 'AUDITORIA', COUNT(*) FROM auditoria
ORDER BY tabla;

SELECT codigo, nombre, estado FROM articulo WHERE estado = 'DISPONIBLE' ORDER BY codigo;
SELECT id_prestamo, fecha_prestamo, fecha_devolucion, estado FROM prestamo WHERE estado = 'ACTIVO' ORDER BY fecha_devolucion;
SELECT id_auditoria, accion, fecha, id_usuario, tabla, descripcion FROM auditoria ORDER BY fecha DESC;
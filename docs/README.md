# Índice de documentación de Galactum

Este índice separa la documentación vigente del estado M2, los registros históricos de M0 y M1 y los documentos que contienen propuestas o decisiones todavía abiertas.

## Documentación actual

| Documento | Propósito |
| --- | --- |
| [README del repositorio](../README.md) | Presentación general, requisitos y ejecución rápida. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Arquitectura actual del cliente, SSS y sincronización de mundo. |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Preparación del entorno con Godot 4.6.2 y ejecución local. |
| [TESTING.md](TESTING.md) | Inventario de pruebas, comandos y resultados esperados. |
| [PROJECT_STATUS.md](PROJECT_STATUS.md) | Progresión M0-M1-M2 y alcance implementado en el hito activo. |
| [Contrato WebSocket](../contracts/sss_protocol_v1.md) | Contratos históricos M0/M1 y sección M2 activa. Su introducción general aún requiere alineación editorial con M2. |

## Documentación histórica

| Documento | Clasificación |
| --- | --- |
| [TEAM3-M0.md](team3/TEAM3-M0.md) | Hito M0 completado. Sus comandos y protocolo describen el estado histórico de M0. |
| [TEAM3-M1-ANDROID.md](team3/TEAM3-M1-ANDROID.md) | Guía de Android correspondiente a M1. Puede servir como referencia, pero no representa por sí sola el runtime M2 actual. |

M0 y M1 permanecen documentados para conservar la trazabilidad del proyecto. No deben interpretarse como la configuración activa cuando contradigan `team3-m2.0`.

## Propuestas y decisiones abiertas

| Documento | Clasificación |
| --- | --- |
| [OPEN_DECISIONS.md](team3/OPEN_DECISIONS.md) | Registro de contradicciones y decisiones pendientes. Incluye referencias a documentación externa que no forma parte de este repositorio. |
| [dashboard-team3-m1.html](dashboard-team3-m1.html) | Dashboard de una propuesta de M1. El propio archivo indica que no representa código implementado. Se conserva como referencia histórica, no como especificación vigente. |

## Fuente de verdad

Para el estado activo se debe consultar, en este orden:

1. El código y la configuración versionados en la rama activa de M2.
2. [PROJECT_STATUS.md](PROJECT_STATUS.md).
3. [ARCHITECTURE.md](ARCHITECTURE.md).
4. La sección M2 del [contrato WebSocket](../contracts/sss_protocol_v1.md).

Si estos documentos contradicen material histórico o una propuesta, la diferencia debe registrarse y resolverse explícitamente. No se debe asumir que un diseño planificado ya está implementado.

# Karmi — Changelog

Este archivo recoge la evolución funcional de Karmi. El código de cada versión se conserva mediante Git; este documento explica qué representa cada generación.

## V2 — Karmi Assistant
**Estado:** En desarrollo

### Objetivo
Transformar Karmi de una adaptación de Coucou con accesos al ecosistema Karma en un asistente nativo, ligero y centralizado para macOS.

La V2 se desarrollará de forma incremental: primero se incorporarán y probarán las nuevas capacidades; después se decidirá qué conservar, qué eliminar y qué mejorar. Solo cuando la versión esté validada se considerará estable.

### Líneas de trabajo previstas
- Integración con ChatGPT / OpenAI.
- Integración con agentes de desarrollo como Codex.
- Integración con GitHub y el ecosistema técnico de Karma.
- Notificaciones relacionadas con las aplicaciones Karma.
- Evolución de la interfaz y del personaje Karmi.
- Voz, conversación y acceso rápido.
- Revisión de las funciones heredadas de V1 antes de decidir si permanecen.

> Esta lista define el punto de partida de V2, no una especificación cerrada.

---

## V1 — Karmi original
**Estado:** Base funcional / versión anterior a V2

### Funciones
- Aplicación nativa para macOS derivada de Coucou.
- Interfaz integrada en la zona superior / notch.
- Activación mediante la zona superior.
- Acceso rápido mediante Option+K.
- Base de interacción por voz/transcripción.
- Funciones heredadas de Coucou sobre las que se construyó Karmi.

### Diseño
- Identidad Karmi.
- Cuerpo negro.
- Ojos blancos.
- Zona superior de activación reducida.
- Interfaz expandible desde la parte superior de macOS.

### Integraciones
- Primera aproximación a la conexión con el ecosistema Karma.
- Trabajo previo para relacionar Karmi con APP / Finance, Work y Care.

### Limitaciones
- V1 nació como adaptación de Coucou y conserva conceptos que se revisarán en V2.
- La función de launcher/acceso a las aplicaciones Karma deja de considerarse el objetivo principal de Karmi.
- Voz, agentes, notificaciones e integración inteligente se consideran áreas a evolucionar en V2.

---

## Política de versiones

- `karma-v1`: referencia de la generación V1.
- `karmi-v2`: rama de desarrollo y experimentación de V2.
- `main`: no se utilizará como laboratorio de V2.
- Las versiones estables futuras deberán quedar identificadas en Git para poder recuperar su código exacto.

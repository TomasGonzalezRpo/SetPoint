# SetPoint 🎾

Gestión de clases de tenis para profesores independientes: alumnos, paquetes, clases, pagos y agenda. PWA instalable en Android.

## Stack

| Capa | Tecnología |
|---|---|
| Frontend | React 18 + Vite + React Router (PWA) |
| Backend | FastAPI (Python 3.12) + Pydantic v2 |
| Base de datos | PostgreSQL en Supabase |
| Auth | Google OAuth 2.0 → JWT en cookie HttpOnly |
| Deploy | Vercel (frontend) + Railway (backend) |

## Arquitectura: mismo dominio

El navegador **solo habla con Vercel**. Vercel reenvía `/api/*` al backend en Railway.
Así la cookie de sesión es *first-party* (`SameSite=Lax`) y no hay problemas de cookies cross-domain.

```
Navegador ──► setpoint.vercel.app ──┬─► /*      → React (estático)
                                    └─► /api/*  → Railway (FastAPI) ──► Supabase
```

En desarrollo, Vite hace lo mismo con su proxy (`/api` → `localhost:8000`).

## Estructura

```
SetPoint/
├── backend/            FastAPI
│   └── app/
│       └── routers/
├── frontend/           React + Vite PWA
└── supabase/
    └── migrations/     SQL del esquema
```

## Reglas de negocio (viven en la BD)

- Inscribir = `alumno_id` + `plan_id`; tipo, minutos, precio y vencimiento se copian solos.
- Una clase `dada` o `falta_cobrada` descuenta minutos; si no alcanza el saldo, se rechaza.
- La clase debe ser del mismo alumno que el plan y hereda su tipo.
- Clase sin plan = suelta: precio automático = tarifa/hora × duración.
- `inscripcion_para_clase()` elige el plan a usar (el que vence primero con saldo).
- Nada con historial se borra: se desactiva o cancela.
- Fechas en hora de Colombia (`hoy()`).
- Vistas: `v_alumnos_resumen` (estado_plan, deuda), `v_inscripciones`, `v_dashboard`.

## Desarrollo

```bash
cd backend
python -m venv .venv && .venv\Scripts\activate   # Windows
pip install -r requirements-dev.txt
pytest                       # pruebas
uvicorn app.main:app --reload
```

## Roadmap

- [x] Paso 1 — Estructura y esquema de BD
- [x] Paso 2 — Backend base + autenticación Google
- [ ] Paso 3 — API: alumnos, planes, inscripciones, clases, pagos, dashboard
- [ ] Paso 4 — Frontend base: layout, diseño, login, proxy
- [ ] Paso 5 — Pantallas
- [ ] Paso 6 — PWA
- [ ] Paso 7 — Deploy

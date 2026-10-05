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

## Roadmap

- [x] Paso 1 — Estructura y esquema de BD
- [ ] Paso 2 — Backend base + autenticación Google
- [ ] Paso 3 — API: alumnos, paquetes, inscripciones, clases, pagos, dashboard
- [ ] Paso 4 — Frontend base: layout, diseño, login, proxy
- [ ] Paso 5 — Pantallas
- [ ] Paso 6 — PWA
- [ ] Paso 7 — Deploy

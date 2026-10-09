import logging

from fastapi import FastAPI

from app.errors import register_error_handlers
from app.routers import auth, tarifas

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")

app = FastAPI(
    title="SetPoint API",
    docs_url="/api/docs",
    openapi_url="/api/openapi.json",
    redoc_url=None,
)
register_error_handlers(app)

# Todas las rutas viven bajo /api (Vercel reenvía /api/* a este backend)
app.include_router(auth.router, prefix="/api")
app.include_router(tarifas.router, prefix="/api")


@app.get("/api/health", tags=["health"])
def health():
    """Healthcheck de Railway: no toca la BD para que un fallo de Supabase no reinicie el contenedor."""
    return {"status": "ok"}


@app.get("/", include_in_schema=False)
def root():
    return {"app": "SetPoint API", "docs": "/api/docs"}

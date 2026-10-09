"""Traduce los errores de la base de datos a respuestas HTTP claras.

Las reglas de negocio viven en Postgres (triggers y constraints). Cuando una se
rompe, Supabase lanza `APIError` con el código SQLSTATE; aquí lo convertimos en
un 4xx con un mensaje que el frontend puede mostrar tal cual.
"""
import logging

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from postgrest.exceptions import APIError

log = logging.getLogger("setpoint")

# SQLSTATE → (status HTTP, mensaje por defecto)
_SQLSTATE = {
    "23514": (409, "Los datos no cumplen las reglas"),        # check_violation
    "23505": (409, "Ya existe un registro con esos datos"),   # unique_violation
    "23503": (409, "Tiene registros asociados o referencia algo que no existe"),  # FK
    "23502": (422, "Falta un dato obligatorio"),              # not_null_violation
    "22P02": (422, "Formato de dato inválido"),               # invalid_text_representation
    "PGRST116": (404, "No encontrado"),                       # .single() sin filas
}


def _mensaje_legible(e: APIError, default: str) -> str:
    msg = e.message or ""
    # Los RAISE de nuestros triggers ya vienen en español y listos para mostrar.
    # Los de Postgres ("new row for relation ... violates check constraint") no.
    if not msg or "violates" in msg or "relation" in msg or "syntax" in msg:
        return default
    return msg


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(APIError)
    async def _db_error(request: Request, e: APIError):
        status, default = _SQLSTATE.get(e.code or "", (500, ""))
        if status >= 500:
            log.error("Error de base de datos en %s: %r", request.url.path, e)
            return JSONResponse({"detail": "Error interno"}, status_code=500)
        return JSONResponse({"detail": _mensaje_legible(e, default)}, status_code=status)

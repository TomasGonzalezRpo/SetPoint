from datetime import datetime, timedelta, timezone
from typing import Annotated

import jwt
from fastapi import Depends, HTTPException, Request, status
from pydantic import BaseModel

from app.config import Settings, get_settings

SESSION_COOKIE = "sp_session"


class User(BaseModel):
    email: str
    name: str | None = None
    picture: str | None = None


def create_session_token(user: User, s: Settings) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user.email,
        "name": user.name,
        "picture": user.picture,
        "iat": now,
        "exp": now + timedelta(days=s.jwt_expire_days),
    }
    return jwt.encode(payload, s.jwt_secret, algorithm=s.jwt_algorithm)


def current_user(request: Request, s: Settings = Depends(get_settings)) -> User:
    """Dependencia: exige una sesión válida. Úsala en todos los routers privados."""
    unauthorized = HTTPException(status.HTTP_401_UNAUTHORIZED, "No autenticado")

    token = request.cookies.get(SESSION_COOKIE)
    if not token:
        raise unauthorized
    try:
        data = jwt.decode(
            token, s.jwt_secret, algorithms=[s.jwt_algorithm],
            options={"require": ["sub", "exp"]},
        )
    except jwt.PyJWTError:
        raise unauthorized

    email = (data.get("sub") or "").lower()
    if email not in s.allowed_email_set:  # por si se quita un correo de la lista
        raise unauthorized
    return User(email=email, name=data.get("name"), picture=data.get("picture"))


# Atajo para los endpoints: `def x(user: CurrentUser): ...`
CurrentUser = Annotated[User, Depends(current_user)]

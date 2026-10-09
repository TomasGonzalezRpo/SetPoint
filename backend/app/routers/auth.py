import base64
import hashlib
import logging
import secrets
from urllib.parse import urlencode

import httpx
from fastapi import APIRouter, Depends, Request, Response
from fastapi.responses import RedirectResponse
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token

from app.config import Settings, get_settings
from app.security import SESSION_COOKIE, CurrentUser, User, create_session_token

log = logging.getLogger("setpoint")
router = APIRouter(prefix="/auth", tags=["auth"])

GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
STATE_COOKIE = "sp_oauth"      # guarda "state.code_verifier" durante el login
STATE_PATH = "/api/auth"

# Reutiliza la sesión HTTP (y la caché de certificados) entre logins
_google_http = google_requests.Request()


def _pkce_pair() -> tuple[str, str]:
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    return verifier, challenge


def _fail(s: Settings, reason: str) -> RedirectResponse:
    resp = RedirectResponse(s.front(f"/login?error={reason}"), status_code=302)
    resp.delete_cookie(STATE_COOKIE, path=STATE_PATH)
    return resp


@router.get("/login")
def login(s: Settings = Depends(get_settings)):
    """Redirige a Google. `state` protege contra CSRF y PKCE contra robo del `code`."""
    state = secrets.token_urlsafe(32)
    verifier, challenge = _pkce_pair()
    params = {
        "client_id": s.google_client_id,
        "redirect_uri": s.google_redirect_uri,
        "response_type": "code",
        "scope": "openid email profile",
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
        "prompt": "select_account",
    }
    resp = RedirectResponse(f"{GOOGLE_AUTH_URL}?{urlencode(params)}", status_code=302)
    resp.set_cookie(
        STATE_COOKIE, f"{state}.{verifier}", max_age=600, httponly=True,
        secure=s.cookie_secure, samesite="lax", path=STATE_PATH,
    )
    return resp


@router.get("/callback")
def callback(
    request: Request,
    code: str | None = None,
    state: str | None = None,
    error: str | None = None,
    s: Settings = Depends(get_settings),
):
    """Google vuelve aquí con `code`. Lo cambiamos por un id_token y creamos la sesión."""
    if error or not code:
        return _fail(s, "cancelado")

    expected_state, _, verifier = (request.cookies.get(STATE_COOKIE) or "").partition(".")
    if not state or not expected_state or not verifier \
            or not secrets.compare_digest(state, expected_state):
        return _fail(s, "state")

    try:
        r = httpx.post(
            GOOGLE_TOKEN_URL,
            data={
                "code": code,
                "client_id": s.google_client_id,
                "client_secret": s.google_client_secret,
                "redirect_uri": s.google_redirect_uri,
                "grant_type": "authorization_code",
                "code_verifier": verifier,
            },
            timeout=10,
        )
        r.raise_for_status()
        info = id_token.verify_oauth2_token(r.json()["id_token"], _google_http, s.google_client_id)
    except Exception:
        log.exception("Falló el intercambio del código con Google")
        return _fail(s, "google")

    email = (info.get("email") or "").lower()
    if not info.get("email_verified") or email not in s.allowed_email_set:
        log.warning("Intento de login no autorizado: %s", email or "<sin email>")
        return _fail(s, "no_autorizado")

    user = User(email=email, name=info.get("name"), picture=info.get("picture"))
    resp = RedirectResponse(s.front("/"), status_code=302)
    resp.set_cookie(
        SESSION_COOKIE, create_session_token(user, s),
        max_age=s.jwt_expire_days * 86400, httponly=True,
        secure=s.cookie_secure, samesite="lax", path="/",
    )
    resp.delete_cookie(STATE_COOKIE, path=STATE_PATH)
    return resp


@router.get("/me", response_model=User)
def me(user: CurrentUser):
    return user


@router.post("/logout", status_code=204)
def logout(response: Response, s: Settings = Depends(get_settings)):
    response.delete_cookie(SESSION_COOKIE, path="/", secure=s.cookie_secure,
                           httponly=True, samesite="lax")

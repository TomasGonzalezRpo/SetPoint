from urllib.parse import parse_qs, urlparse

import pytest
from fastapi.testclient import TestClient
from postgrest.exceptions import APIError

from app.config import get_settings
from app.main import app
from app.routers import auth as auth_mod
from app.security import SESSION_COOKIE, User, create_session_token


@pytest.fixture
def client():
    return TestClient(app, follow_redirects=False)


def token_para(email: str) -> str:
    return create_session_token(User(email=email), get_settings())


def test_health(client):
    assert client.get("/api/health").json() == {"status": "ok"}


def test_me_sin_sesion(client):
    assert client.get("/api/auth/me").status_code == 401


def test_me_con_sesion(client):
    client.cookies.set(SESSION_COOKIE, token_para("profe@gmail.com"))
    assert client.get("/api/auth/me").json()["email"] == "profe@gmail.com"


def test_correo_en_mayusculas_permitido(client):
    client.cookies.set(SESSION_COOKIE, token_para("OTRO@gmail.com"))
    assert client.get("/api/auth/me").status_code == 200


def test_correo_retirado_de_la_lista(client):
    client.cookies.set(SESSION_COOKIE, token_para("intruso@gmail.com"))
    assert client.get("/api/auth/me").status_code == 401


def test_token_alterado(client):
    client.cookies.set(SESSION_COOKIE, token_para("profe@gmail.com") + "x")
    assert client.get("/api/auth/me").status_code == 401


def test_login_redirige_con_state_y_pkce(client):
    r = client.get("/api/auth/login")
    assert r.status_code == 302
    q = parse_qs(urlparse(r.headers["location"]).query)
    assert q["code_challenge_method"] == ["S256"]
    cookie = r.cookies.get(auth_mod.STATE_COOKIE)
    assert cookie and cookie.split(".")[0] == q["state"][0]


def test_callback_state_invalido(client):
    client.get("/api/auth/login")
    r = client.get("/api/auth/callback", params={"code": "c", "state": "otro"})
    assert r.headers["location"].endswith("/login?error=state")


def test_callback_cancelado(client):
    r = client.get("/api/auth/callback", params={"error": "access_denied"})
    assert r.headers["location"].endswith("/login?error=cancelado")


def _login_simulado(client, monkeypatch, email):
    class FakeResp:
        def raise_for_status(self): ...
        def json(self): return {"id_token": "tok"}

    sent = {}
    monkeypatch.setattr(auth_mod.httpx, "post", lambda url, data, timeout: sent.update(data) or FakeResp())
    monkeypatch.setattr(auth_mod.id_token, "verify_oauth2_token",
                        lambda tok, req, aud: {"email": email, "email_verified": True, "name": "Profe"})
    r = client.get("/api/auth/login")
    state = parse_qs(urlparse(r.headers["location"]).query)["state"][0]
    return client.get("/api/auth/callback", params={"code": "c", "state": state}), sent


def test_callback_ok_crea_sesion(client, monkeypatch):
    r, sent = _login_simulado(client, monkeypatch, "profe@gmail.com")
    assert r.headers["location"] == "http://localhost:5173/"
    assert sent["code_verifier"]
    assert client.get("/api/auth/me").json()["name"] == "Profe"


def test_callback_correo_no_autorizado(client, monkeypatch):
    r, _ = _login_simulado(client, monkeypatch, "intruso@gmail.com")
    assert r.headers["location"].endswith("/login?error=no_autorizado")
    assert SESSION_COOKIE not in r.cookies


def test_logout_borra_cookie(client):
    client.cookies.set(SESSION_COOKIE, token_para("profe@gmail.com"))
    r = client.post("/api/auth/logout")
    assert r.status_code == 204
    assert 'sp_session=""' in r.headers["set-cookie"]


@pytest.mark.parametrize("code,msg,status,esperado", [
    ("23514", "Saldo insuficiente: el plan tiene 240 min y quedaría con 300 min usados", 409, "Saldo insuficiente"),
    ("23514", 'new row for relation "x" violates check constraint "y"', 409, "Los datos no cumplen las reglas"),
    ("23503", "update or delete on table violates foreign key", 409, "Tiene registros asociados"),
    ("XX000", "boom", 500, "Error interno"),
])
def test_errores_bd(client, code, msg, status, esperado):
    @app.get("/api/_test_error_" + code + str(status) + esperado[:3])
    def boom():
        raise APIError({"code": code, "message": msg})
    client.cookies.clear()
    r = client.get("/api/_test_error_" + code + str(status) + esperado[:3])
    assert r.status_code == status
    assert r.json()["detail"].startswith(esperado)

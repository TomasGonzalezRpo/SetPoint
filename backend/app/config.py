from functools import lru_cache

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Supabase
    supabase_url: str
    supabase_service_key: str

    # Google OAuth
    google_client_id: str
    google_client_secret: str
    google_redirect_uri: str

    # Sesión
    jwt_secret: str
    jwt_algorithm: str = "HS256"
    jwt_expire_days: int = 30
    allowed_emails: str

    # Frontend
    frontend_url: str = "http://localhost:5173"

    @field_validator("jwt_secret")
    @classmethod
    def _secret_largo(cls, v: str) -> str:
        if len(v) < 32:
            raise ValueError("JWT_SECRET debe tener al menos 32 caracteres")
        return v

    @property
    def allowed_email_set(self) -> set[str]:
        return {e.strip().lower() for e in self.allowed_emails.split(",") if e.strip()}

    @property
    def cookie_secure(self) -> bool:
        """Cookies `Secure` cuando el frontend corre en HTTPS (producción)."""
        return self.frontend_url.startswith("https://")

    def front(self, path: str = "/") -> str:
        return self.frontend_url.rstrip("/") + path


@lru_cache
def get_settings() -> Settings:
    return Settings()

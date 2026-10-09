import os

# Variables falsas para que la app arranque sin .env
os.environ.update({
    "SUPABASE_URL": "https://test.supabase.co",
    "SUPABASE_SERVICE_KEY": "test",
    "GOOGLE_CLIENT_ID": "client-id",
    "GOOGLE_CLIENT_SECRET": "secret",
    "GOOGLE_REDIRECT_URI": "http://localhost:8000/api/auth/callback",
    "JWT_SECRET": "x" * 48,
    "ALLOWED_EMAILS": "profe@gmail.com, Otro@Gmail.com",
    "FRONTEND_URL": "http://localhost:5173",
})

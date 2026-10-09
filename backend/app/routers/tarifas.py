from fastapi import APIRouter, Depends

from app.db import get_db
from app.security import current_user

router = APIRouter(prefix="/tarifas", tags=["tarifas"], dependencies=[Depends(current_user)])


@router.get("")
def listar_tarifas():
    """Tarifa por hora de clases sin plan. Sirve también para probar la conexión a Supabase."""
    return get_db().table("tarifas").select("*").order("precio_hora").execute().data

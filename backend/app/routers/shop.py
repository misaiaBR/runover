"""Mercado interno: catálogo, carteira, inventário, compra e equipamento."""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.database import get_db, lock_mutations
from app.core.security import get_current_user
from app.models import CoinTransaction, User, UserItem
from app.schemas import (
    EquipRequest,
    Inventory,
    PurchaseRequest,
    ShopItem,
    Wallet,
    WalletEntry,
)
from app.services.coins import debit
from app.services.shop import CATEGORIES, EQUIPPABLE, SCOPES, get_item, list_items

router = APIRouter(prefix="/shop", tags=["mercado"])

MAX_EQUIPPED_EMOTICONS = 4


def _inventory_of(db: Session, user: User) -> Inventory:
    owned = [
        item_id
        for (item_id,) in db.query(UserItem.item_id)
        .filter(UserItem.user_id == user.id)
        .all()
    ]
    return Inventory(
        owned=owned,
        equipped_avatar=user.equipped_avatar,
        equipped_frame=user.equipped_frame,
        equipped_effect=user.equipped_effect,
        equipped_banner=user.equipped_banner,
        equipped_name_style=user.equipped_name_style,
        equipped_emoticons=[e for e in (user.equipped_emoticons or "").split(",") if e],
    )


@router.get("/catalog", response_model=list[ShopItem])
def catalog(
    category: str | None = Query(default=None),
    scope: str | None = Query(default=None),
):
    if category is not None and category not in CATEGORIES:
        raise HTTPException(400, "Categoria inválida.")
    if scope is not None and scope not in SCOPES:
        raise HTTPException(400, "Escopo inválido.")
    return list_items(category, scope)


@router.get("/wallet", response_model=Wallet)
def wallet(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    transactions = (
        db.query(CoinTransaction)
        .filter(CoinTransaction.user_id == user.id)
        .order_by(CoinTransaction.created_at.desc())
        .limit(50)
        .all()
    )
    return Wallet(
        balance=user.coins_balance or 0,
        transactions=[
            WalletEntry(delta=t.delta, reason=t.reason, created_at=t.created_at)
            for t in transactions
        ],
    )


@router.get("/inventory", response_model=Inventory)
def inventory(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _inventory_of(db, user)


@router.post("/purchase", response_model=Inventory)
def purchase(
    data: PurchaseRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = get_item(data.item_id)
    if item is None:
        raise HTTPException(404, "Item não encontrado.")
    if item.get("scope") == "team":
        raise HTTPException(400, "Este item é da loja da equipe.")
    if item.get("scope") == "pass":
        raise HTTPException(400, "Este item é exclusivo do Pass Runover.")
    lock_mutations(db)
    db.refresh(user)
    if item["category"] == "bundle":
        return _purchase_bundle(db, user, item)
    existing = (
        db.query(UserItem)
        .filter(UserItem.user_id == user.id, UserItem.item_id == item["id"])
        .first()
    )
    if existing:
        raise HTTPException(409, "Você já possui este item.")
    debit(db, user, item["price"], f"compra:{item['id']}")
    db.add(UserItem(user_id=user.id, item_id=item["id"]))
    db.commit()
    db.refresh(user)
    return _inventory_of(db, user)


def _purchase_bundle(db: Session, user: User, bundle: dict) -> Inventory:
    """Pacote: libera cada item de `grants` que o usuário ainda não tem."""
    from app.services.shop import get_item as _get

    grants = [g for g in bundle["payload"].get("grants", []) if _get(g)]
    if not grants:
        raise HTTPException(400, "Pacote inválido.")
    owned_ids = {
        item_id
        for (item_id,) in db.query(UserItem.item_id)
        .filter(UserItem.user_id == user.id)
        .all()
    }
    if all(g in owned_ids for g in grants):
        raise HTTPException(409, "Você já possui todos os itens do pacote.")
    debit(db, user, bundle["price"], f"compra:{bundle['id']}")
    for item_id in grants:
        if item_id not in owned_ids:
            db.add(UserItem(user_id=user.id, item_id=item_id))
    db.add(UserItem(user_id=user.id, item_id=bundle["id"]))
    db.commit()
    db.refresh(user)
    return _inventory_of(db, user)


@router.post("/equip", response_model=Inventory)
def equip(
    data: EquipRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    category = data.category
    if category == "emoticon":
        return _equip_emoticons(db, user, data.item_id)
    if category not in EQUIPPABLE:
        raise HTTPException(400, "Categoria inválida.")
    lock_mutations(db)
    column = f"equipped_{category}"
    if data.item_id is None:
        setattr(user, column, None)
        db.commit()
        db.refresh(user)
        return _inventory_of(db, user)
    item = get_item(data.item_id)
    if item is None or item["category"] != category:
        raise HTTPException(404, "Item não encontrado nesta categoria.")
    # Só a loja do usuário e o passe equipam aqui: itens da equipe têm o
    # fluxo próprio do cofre. Itens do passe nunca são concedidos de graça —
    # só o resgate (POST /pass/claim) entrega; sem ele, nem equipa.
    if item.get("scope", "user") not in ("user", "pass"):
        raise HTTPException(404, "Item não encontrado nesta categoria.")
    owned = (
        db.query(UserItem)
        .filter(UserItem.user_id == user.id, UserItem.item_id == item["id"])
        .first()
    )
    if owned is None and item.get("scope", "user") == "pass":
        raise HTTPException(404, "Item não encontrado nesta categoria.")
    if owned is None and item["price"] != 0:
        raise HTTPException(403, "Compre o item antes de equipar.")
    if owned is None and item["price"] == 0:
        db.add(UserItem(user_id=user.id, item_id=item["id"]))
    setattr(user, column, item["id"])
    db.commit()
    db.refresh(user)
    return _inventory_of(db, user)


def _equip_emoticons(db: Session, user: User, item_id: str | None) -> Inventory:
    """Equipa um pacote de emoticons (mostra os emojis no perfil, máx 4)."""
    lock_mutations(db)
    if item_id is None:
        user.equipped_emoticons = ""
        db.commit()
        db.refresh(user)
        return _inventory_of(db, user)
    item = get_item(item_id)
    if item is None or item["category"] != "emoticon":
        raise HTTPException(404, "Item não encontrado nesta categoria.")
    if item.get("scope", "user") != "user":
        raise HTTPException(404, "Item não encontrado nesta categoria.")
    owned = (
        db.query(UserItem)
        .filter(UserItem.user_id == user.id, UserItem.item_id == item["id"])
        .first()
    )
    if owned is None and item["price"] != 0:
        raise HTTPException(403, "Compre o item antes de equipar.")
    if owned is None and item["price"] == 0:
        db.add(UserItem(user_id=user.id, item_id=item["id"]))
    current = [e for e in (user.equipped_emoticons or "").split(",") if e]
    for emoji in item["payload"].get("emoji", []):
        if emoji not in current:
            current.append(emoji)
    user.equipped_emoticons = ",".join(current[:MAX_EQUIPPED_EMOTICONS])
    db.commit()
    db.refresh(user)
    return _inventory_of(db, user)

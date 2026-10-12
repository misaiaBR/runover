"""Política de endereço de e-mail no cadastro.

O portão de confirmação só serve se o endereço significar uma caixa de correio
que a pessoa controla. Domínio descartável não significa, e o mesmo endereço com
maiúscula trocada ou com uma etiqueta `+r1` no nome não é outra caixa. As duas
coisas são corrigidas aqui, na entrada, antes de o usuário existir no banco.
"""

DISPOSABLE_EMAIL_DOMAINS = frozenset(
    {
        "10minutemail.com",
        "20minutemail.com",
        "dispostable.com",
        "emailondeck.com",
        "emailtemporario.com.br",
        "fakeinbox.com",
        "getairmail.com",
        "getnada.com",
        "guerrillamail.com",
        "guerrillamail.info",
        "maildrop.cc",
        "mailinator.com",
        "mintemail.com",
        "mohmal.com",
        "sharklasers.com",
        "spam4.me",
        "spamgourmet.com",
        "temp-mail.org",
        "tempail.com",
        "tempr.email",
        "tempmail.com",
        "throwawaymail.com",
        "trashmail.com",
        "yopmail.com",
    }
)


def normalize_email(value: str) -> str:
    """Minúsculas, sem espaços e sem a etiqueta que vem depois de `+`.

    `Ana@Exemplo.com`, `ana@example.com`, `ana+r1@example.com` e
    `ana+r2@example.com` abrem a mesma caixa de correio. Enquanto cada grafia
    virar uma conta, o portão de confirmação é burocracia: quem cria contas em
    série troca o sufixo e recebe um código novo quantas vezes quiser. A
    etiqueta só é cortada quando sobra um nome de caixa — endereço que começa com
    `+` não tem parte local para dobrar, e as duas regras valem para todo mundo
    que pede um e-mail (cadastro, login, código, recuperação).
    """
    cleaned = value.strip().lower()
    local, at, domain = cleaned.partition("@")
    if not at or "+" not in local:
        return cleaned
    base = local.split("+", 1)[0]
    return f"{base}@{domain}" if base else cleaned


def email_domain(value: str) -> str:
    return normalize_email(value).rsplit("@", 1)[-1]


def is_disposable(value: str) -> bool:
    return email_domain(value) in DISPOSABLE_EMAIL_DOMAINS

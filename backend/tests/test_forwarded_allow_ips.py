"""O contrato de proxy por trás do throttle por IP do auth.

`backend/app/routers/auth.py` só diferencia um jogador de outro pelo
`request.client.host`, e quem escreve esse campo é o middleware de proxy do
uvicorn a partir do `X-Forwarded-For`. Para isso a lista de proxies confiáveis
precisa casar com o endereço do Render — e as versões do uvicorn até 0.30.6
comparavam esse endereço por igualdade de texto, sem interpretar redes: um
`10.0.0.0/8` no Blueprint nunca casava, o middleware nem olhava o header e todo
mundo passava a dividir o mesmo balde de tentativas.

Os testes amarram as três pontas que precisam concordar: o pino em
`backend/requirements.txt`, o valor em `render.yaml` e o comando em `Dockerfile`.
Não há fixture de banco aqui — é contrato de configuração, não de aplicação.
"""

import ipaddress
from pathlib import Path

import pytest
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware

REPO_ROOT = Path(__file__).resolve().parents[2]


async def _noop_app(scope, receive, send):
    """Alvo vazio: o que interessa é como o middleware interpreta a lista."""


def _trusted_hosts(entries):
    """O container de hosts confiáveis da versão do uvicorn instalada."""
    return ProxyHeadersMiddleware(_noop_app, trusted_hosts=entries).trusted_hosts


def _forwarded_allow_ips_from_blueprint() -> str:
    """O valor de `FORWARDED_ALLOW_IPS` declarado no Blueprint do Render."""
    lines = (REPO_ROOT / "render.yaml").read_text(encoding="utf-8").splitlines()
    for index, line in enumerate(lines):
        if line.strip() == "- key: FORWARDED_ALLOW_IPS":
            return lines[index + 1].split("value:", 1)[1].strip().strip('"')
    raise AssertionError("render.yaml precisa declarar FORWARDED_ALLOW_IPS.")


def _entries() -> list[str]:
    value = _forwarded_allow_ips_from_blueprint()
    return [item.strip() for item in value.split(",") if item.strip()]


def test_pinned_uvicorn_understands_cidr_trusted_hosts():
    """O pino tem que ser de uma versão que leia redes, não só endereços soltos.

    É o que faltava no 0.30.6: aqui `10.0.0.0/8` vira rede e casa por
    pertencimento, que é o caso do Render em produção.
    """
    trusted = _trusted_hosts("10.0.0.0/8")
    assert "10.7.8.9" in trusted
    assert "11.7.8.9" not in trusted


def test_blueprint_lists_only_addresses_and_networks():
    """Nada do Blueprint sobra como texto: CIDR mal escrito é mudo."""
    trusted = _trusted_hosts(_entries())
    assert trusted.trusted_literals == set()
    assert trusted.trusted_hosts and trusted.trusted_networks


def test_blueprint_trusts_the_proxy_addresses_it_describes():
    """Os endereços que chegam do Render e das bordas da Cloudflare são aceitos."""
    trusted = _trusted_hosts(_entries())
    for address in (
        "127.0.0.1",  # loopback: health check e teste local
        "10.19.32.7",  # 10.0.0.0/8 — rede interna do Render
        "172.20.4.8",  # 172.16.0.0/12
        "192.168.5.5",  # 192.168.0.0/16
        "104.16.10.11",  # 104.16.0.0/13
        "173.245.48.20",  # primeira faixa pública da Cloudflare
        "2606:4700:4700::6812:a",  # borda IPv6 da Cloudflare
    ):
        assert address in trusted, address


def test_blueprint_does_not_trust_a_random_client():
    """Um jogador qualquer continua de fora.

    Sem isso o `X-Forwarded-For` do próprio cliente seria aceito e o throttle
    passaria a confiar num header forjável.
    """
    trusted = _trusted_hosts(_entries())
    for address in ("8.8.8.8", "172.32.0.1", "2001:4860:4860::8888"):
        assert address not in trusted, address


@pytest.mark.parametrize("entry", _entries())
def test_every_entry_is_a_valid_address_or_network(entry):
    """Cada linha da lista é um endereço ou uma rede válida."""
    if "/" in entry:
        assert ipaddress.ip_network(entry).network_address.version in (4, 6)
    else:
        assert ipaddress.ip_address(entry).version in (4, 6)


def test_dockerfile_wires_the_blueprint_into_the_server():
    """O container liga `--proxy-headers` e passa a lista lida do ambiente.

    Faltando uma das duas, o `FORWARDED_ALLOW_IPS` do Blueprint é enfeite.
    """
    command = (REPO_ROOT / "Dockerfile").read_text(encoding="utf-8")
    assert "--proxy-headers" in command
    assert "--forwarded-allow-ips" in command
    assert "FORWARDED_ALLOW_IPS" in command

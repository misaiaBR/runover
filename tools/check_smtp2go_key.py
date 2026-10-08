#!/usr/bin/env python3
"""Diagnostica a chave SMTP2GO usada pelo envio de e-mails do backend.

Consulta `POST /api_keys/view` e confere, sem expor segredos, se a chave
que o Render usa em `SMTP2GO_API_KEY` está `allowed` e tem acesso ao
`/email/send` — as duas causas mais comuns do sintoma "não recebi o
código" com o boot log silencioso.

Uso (a chave vai por ambiente para não vazar no histórico do shell):

    SMTP2GO_API_KEY=sua-chave python3 tools/check_smtp2go_key.py
    SMTP2GO_API_KEY=sua-chave python3 tools/check_smtp2go_key.py --region eu

Saída 0: chave pronta para enviar. Saída 1: chave bloqueada/sandbox ou
sem o endpoint. Saída 2: falha de requisição (rede, chave inválida para
a própria consulta, região errada).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

REGIONS = {
    "global": "https://api.smtp2go.com/v3",
    "us": "https://us-api.smtp2go.com/v3",
    "eu": "https://eu-api.smtp2go.com/v3",
    "au": "https://au-api.smtp2go.com/v3",
}


def view_keys(api_key: str, base: str, payload: dict) -> dict:
    request = urllib.request.Request(
        base + "/api_keys/view",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "X-Smtp2go-Api-Key": api_key,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        try:
            detail = json.load(exc)
            error = detail.get("data", {}).get("error", exc.reason)
        except ValueError:
            error = exc.reason
        print(f"SMTP2GO recusou a consulta (HTTP {exc.code}): {error}", file=sys.stderr)
        raise SystemExit(2)
    except OSError as exc:
        print(f"Falha de rede ao chamar a SMTP2GO: {exc}", file=sys.stderr)
        raise SystemExit(2)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--key",
        default=os.environ.get("SMTP2GO_API_KEY", ""),
        help="Chave SMTP2GO (prefira a variável de ambiente SMTP2GO_API_KEY).",
    )
    parser.add_argument(
        "--region",
        choices=sorted(REGIONS),
        default="global",
        help="Região da conta SMTP2GO (padrão: global).",
    )
    parser.add_argument("--id", default="", help="Detalha só esta chave completa.")
    parser.add_argument("--search", default="", help="Filtra pela descrição.")
    args = parser.parse_args()

    if not args.key:
        print(
            "Informe a chave via SMTP2GO_API_KEY ou --key (ela não é gravada em nada).",
            file=sys.stderr,
        )
        return 2

    payload: dict[str, str] = {}
    if args.id:
        payload["id"] = args.id
    if args.search:
        payload["search"] = args.search
    body = view_keys(args.key, REGIONS[args.region], payload)

    entries = body.get("data", [])
    if not entries:
        print("Nenhuma chave retornada. Confira a região (--region).")
        return 2

    problems = 0
    for entry in entries:
        status = entry.get("status", "?")
        endpoints = entry.get("endpoints", [])
        print(f"- {entry.get('api_key', '?')} ({entry.get('description', '') or 'sem descrição'})")
        print(f"  status: {status} | endpoints: {', '.join(endpoints) or '(nenhum)'}")
        if status != "allowed":
            print("  AVISO: chave não está allowed; o envio falha.", file=sys.stderr)
            problems += 1
        elif "/email/send" not in endpoints:
            print("  AVISO: sem acesso a /email/send; o backend recebe ENDPOINT_PERMISSION_DENIED.", file=sys.stderr)
            problems += 1
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())

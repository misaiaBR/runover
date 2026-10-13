"""Catálogo do mercado interno (moedas + cosméticos).

O catálogo é versionado em código (sem painel admin no MVP): cada item tem
`id`, `category`, `name`, `price` (em moedinhas) e um `payload` com os dados
visuais que o app usa para renderizar (cores, emoji, asset, animação).

Categorias:
- `avatar`: decorações de avatar da galeria pronta (`asset`) ou gerados
  via DiceBear (`generated` = estilo, seed = apelido do dono) — os
  `animated` ganham animação no app sem precisar de GIF/WebP.
- `frame`: molduras de perfil.
- `effect`: efeitos de perfil (partículas/brilho animados no app).
- `banner`: placas de identificação — faixas de perfil (gradiente).
- `name_style`: placas de identificação — estilo do nome exibido.
- `emoticon`: pacotes de emoticons exibidos no perfil.
- `bundle`: pacotes com vários itens por um preço menor (compra libera
  cada item do `payload['grants']`).

Seções da loja no app (biblioteca com categorias): Decorações de avatar,
Placas de Identificação, Efeitos de perfil, Molduras de Perfil, Pacotes,
Disponíveis com Orbs (moedinhas ganhas correndo) e Parcerias
(`payload['collection'] == 'parceria').

Loja da equipe (`scope == 'team'`): decoração, molduras, efeitos, faixas e
estilos de nome da equipe, com valores altos em pontos. O saldo é o cofre
da equipe — soma dos pontos dos integrantes menos o já gasto (`spent_points`);
ninguém perde nível ou posição ao comprar. Compra e equipamento só pelo
dono ou admins; ver `app/services/team_shop.py` e as rotas em `/teams`.
"""

from __future__ import annotations

CATEGORIES = ("avatar", "frame", "effect", "banner", "name_style", "emoticon", "bundle")
SCOPES = ("user", "team", "pass")
ORB_COLLECTION = "orbs"  # tudo se compra com Orbs (moedinhas ganhas correndo)
PARTNER_COLLECTION = "parceria"

# Equipamento usa uma coluna por categoria (exceto emoticons, que é lista).
EQUIPPABLE = ("avatar", "frame", "effect", "banner", "name_style")


def _item(
    item_id: str,
    category: str,
    name: str,
    price: int,
    scope: str = "user",
    **payload,
) -> dict:
    return {
        "id": item_id,
        "category": category,
        "name": name,
        "price": price,
        "scope": scope,
        "payload": payload,
    }


CATALOG_BASE: list[dict] = [
    # ---- Avatares da galeria ----
    # A arte vem da API de avatares (estilo + seed), não de uma biblioteca
    # própria de PNGs: é o que permite a cada item ter rosto próprio. O `seed`
    # é o id do item — posto em `_normalize` abaixo — então a loja, o perfil de
    # quem equipou e o cartão de ranking mostram sempre a mesma figura.
    # Tudo custa moedas: nenhum item tem preço 0 (a galeria do app compra
    # e equipa estes mesmos itens — sem bypass gratuito).
    _item("avatar_corredor", "avatar", "Corredor", 50, generated="adventurer"),
    _item("avatar_coroa", "avatar", "Coroa", 150, generated="personas"),
    _item("avatar_raio", "avatar", "Raio animado", 400, generated="thumbs"),
    _item("avatar_chama", "avatar", "Chama animada", 600, generated="bottts"),
    _item("avatar_sol", "avatar", "Sol", 180, generated="avataaars"),
    _item("avatar_lua", "avatar", "Lua", 180, generated="lorelei"),
    _item("avatar_onda", "avatar", "Onda", 220, generated="notionists"),
    _item("avatar_pico", "avatar", "Pico", 220, generated="pixel-art"),
    _item("avatar_estrela", "avatar", "Estrela", 300, generated="adventurer"),
    _item("avatar_bandeira", "avatar", "Bandeira", 300, generated="avataaars"),
    _item("avatar_cometa", "avatar", "Cometa animado", 450, generated="bottts"),
    _item("avatar_escudo", "avatar", "Escudo", 350, generated="personas"),
    # ---- Avatares gerados (estilos alternativos da mesma API) ----
    _item("avatar_gerado_adventurer", "avatar", "Gerado aventureiro", 250, generated="adventurer", animated=False),
    _item("avatar_gerado_avataaars", "avatar", "Gerado avatar", 250, generated="avataaars", animated=False),
    _item("avatar_gerado_bottts", "avatar", "Gerado robô", 300, generated="bottts", animated=False),
    _item("avatar_gerado_personas", "avatar", "Gerado persona", 350, generated="personas", animated=False),
    _item("avatar_gerado_notionists", "avatar", "Gerado notion", 400, generated="notionists", animated=False),
    _item("avatar_gerado_thumbs", "avatar", "Gerado polegar", 450, generated="thumbs", animated=False),
    _item("avatar_gerado_pixel_art", "avatar", "Gerado pixel", 500, generated="pixel-art", animated=False),
    _item("avatar_gerado_lorelei", "avatar", "Gerado lorelei", 600, generated="lorelei", animated=False),
    # ---- Molduras ----
    # `style` é a família de acabamento que o app desenha; `grade`, `ornament`
    # e companhia são os parâmetros dela. Ver `FRAME_STYLES` abaixo.
    _item("frame_bronze", "frame", "Moldura bronze", 100,
          style="metal", grade="bronze", ornament="none",
          colors=["#CD7F32"], animated=False),
    _item("frame_prata", "frame", "Moldura prata", 250,
          style="metal", grade="prata", ornament="jewel",
          colors=["#C0C0C0"], animated=False),
    _item("frame_ouro", "frame", "Moldura ouro", 500,
          style="metal", grade="ouro", ornament="wings",
          colors=["#FFC93C", "#FF7F4D"], animated=False),
    _item("frame_neon", "frame", "Moldura neon animada", 800,
          style="chroma", colors=["#3DDBB0", "#8B7CFF"], animated=True),
    # ---- Efeitos de perfil ----
    _item("effect_faísca", "effect", "Faíscas", 300,
          kind="sparkle", density=7, cycle_ms=2400, hue=45),
    _item("effect_chamas", "effect", "Chamas", 600,
          kind="fire", density=9, cycle_ms=2100, hue=18),
    # ---- Faixas de perfil (placas de fundo) ----
    _item("banner_oceano", "banner", "Oceano", 200,
          plate="gradient", colors=["#0EA5E9", "#1E3A8A"]),
    _item("banner_pôr_do_sol", "banner", "Pôr do sol", 350,
          plate="shimmer", colors=["#FF7F4D", "#8B7CFF"]),
    _item("banner_galáxia", "banner", "Galáxia", 600,
          plate="glass", colors=["#2A2240", "#8B7CFF", "#3DDBB0"]),
    # ---- Estilos de nome ----
    _item("name_neon", "name_style", "Nome neon", 250, colors=["#3DDBB0"], glow=True),
    _item("name_ouro", "name_style", "Nome ouro", 400, colors=["#FFC93C"], glow=True),
    _item("name_arco_íris", "name_style", "Nome arco-íris", 700, colors=["#FF7F4D", "#FFC93C", "#3DDBB0", "#8B7CFF"], glow=False),
    # ---- Emoticons exibidos no perfil ----
    # `depth` é o material da peça, `motion` é como ela entra em cena, `badge`
    # é o distintivo no canto do avatar e `trail` solta miniaturas subindo.
    _item("emoticon_troféu", "emoticon", "Troféu", 150, emoji=["🏆"],
          depth="volumetric", motion="heartbeat", badge="corner",
          trail=True, tint="#FFC93C"),
    _item("emoticon_raio", "emoticon", "Raio", 150, emoji=["⚡"],
          depth="glass", motion="pop_spin", badge="none",
          trail=False, tint="#8B7CFF"),
    _item("emoticon_campeão", "emoticon", "Pacote campeão", 400, emoji=["🏆", "🔥", "⚡", "🏅"],
          depth="lifted", motion="spring", badge="ring",
          trail=True, tint="#3DDBB0"),
    # ---- Parcerias ----
    _item("frame_torcida", "frame", "Moldura torcida (parceria)", 450,
          colors=["#16A34A", "#FFC93C"], animated=False, collection="parceria"),
    _item("banner_torcida", "banner", "Faixa torcida (parceria)", 400,
          colors=["#16A34A", "#FFFFFF"], collection="parceria"),
    _item("emoticon_torcida", "emoticon", "Pacote torcida (parceria)", 250,
          emoji=["📣", "🎉", "💚"], depth="glass", motion="float",
          badge="corner", trail=True, tint="#16A34A", collection="parceria"),
    # ---- Pacotes (preço menor que a soma) ----
    _item("pacote_iniciante", "bundle", "Pacote iniciante", 350,
          grants=["avatar_coroa", "frame_bronze", "banner_oceano"]),
    _item("pacote_campeão", "bundle", "Pacote campeão", 900,
          grants=["frame_ouro", "effect_faísca", "name_ouro"]),
    # ---- Loja da equipe (scope team, valores altos em pontos) ----
    # Os itens da equipe usam o mesmo vocabulário visual da loja pessoal: a loja
    # da equipe é uma vitrine, não uma lista de cores soltas.
    _item("team_avatar_estandarte", "avatar", "Estandarte da equipe", 4000, "team",
          generated="adventurer", light="top", depth="inner", texture="grain",
          tint="#FFE9C9"),
    _item("team_avatar_escudo", "avatar", "Escudo da equipe", 6000, "team",
          generated="personas", light="rim", depth="bevel", texture="hex",
          tint="#CFD8FF"),
    _item("team_avatar_coroa", "avatar", "Coroa da equipe", 9000, "team",
          generated="avataaars", light="back", depth="inner", texture="brushed",
          tint="#FFF3C4"),
    _item("team_avatar_cometa", "avatar", "Cometa da equipe", 12000, "team",
          generated="bottts", light="side", depth="flat", texture="dots",
          tint="#C9E7FF"),
    _item("team_avatar_chama", "avatar", "Chama da equipe", 18000, "team",
          generated="thumbs", light="rim", depth="bevel", texture="carbon",
          tint="#FFD1A1"),
    _item("team_frame_ferro", "frame", "Moldura ferro da equipe", 5000, "team",
          style="faction", texture="carbon", colors=["#57534E"], animated=False),
    _item("team_frame_prata", "frame", "Moldura prata da equipe", 8000, "team",
          style="metal", grade="prata", ornament="none", colors=["#E5E7EB"],
          animated=False),
    _item("team_frame_ouro", "frame", "Moldura ouro da equipe", 12000, "team",
          style="metal", grade="ouro", ornament="wings",
          colors=["#FFC93C", "#FF7F4D"], animated=False),
    _item("team_frame_fogo", "frame", "Moldura fogo da equipe", 20000, "team",
          style="chroma", speed_ms=1800, colors=["#EF4444", "#F59E0B"],
          animated=True),
    _item("team_frame_lendaria", "frame", "Moldura lendária da equipe", 30000, "team",
          style="metal", grade="diamante", ornament="jewel",
          colors=["#8B5CF6", "#3DDBB0", "#FFC93C"], animated=True),
    _item("team_effect_faisca", "effect", "Faíscas da equipe", 8000, "team",
          kind="sparkle", density=8, cycle_ms=2200, hue=200),
    _item("team_effect_chamas", "effect", "Chamas da equipe", 15000, "team",
          kind="fire", density=10, cycle_ms=2000, hue=18),
    _item("team_effect_tormenta", "effect", "Tormenta da equipe", 25000, "team",
          kind="storm", density=12, cycle_ms=1700, hue=250),
    _item("team_effect_inferno", "effect", "Inferno da equipe", 40000, "team",
          kind="fire", density=16, cycle_ms=1300, hue=8),
    _item("team_banner_bau", "banner", "Faixa baú da equipe", 6000, "team",
          plate="carbon", weave=2, colors=["#92400E", "#F59E0B"]),
    _item("team_banner_muralha", "banner", "Faixa muralha da equipe", 10000, "team",
          plate="territory", region="Sudeste", colors=["#57534E", "#A8A29E"]),
    _item("team_banner_horizonte", "banner", "Faixa horizonte da equipe", 16000, "team",
          plate="gradient", angle=35, colors=["#0EA5E9", "#8B7CFF"]),
    _item("team_banner_tempestade", "banner", "Faixa tempestade da equipe", 25000, "team",
          plate="parallax", depth=2, colors=["#1E1B4B", "#6366F1", "#22D3EE"]),
    _item("team_banner_gloria", "banner", "Faixa glória da equipe", 40000, "team",
          plate="brushed", grade="ouro", colors=["#FFC93C", "#FF7F4D", "#8B5CF6"]),
    _item("team_name_guerreiro", "name_style", "Nome guerreiro da equipe", 5000, "team", colors=["#E5E7EB"], glow=False),
    _item("team_name_capitao", "name_style", "Nome capitão da equipe", 9000, "team", colors=["#3DDBB0"], glow=True),
    _item("team_name_lenda", "name_style", "Nome lenda da equipe", 14000, "team", colors=["#FFC93C"], glow=True),
    _item("team_name_mito", "name_style", "Nome mito da equipe", 22000, "team", colors=["#FF7F4D", "#FFC93C", "#3DDBB0", "#8B7CFF"], glow=True),
    _item("team_pacote_batalha", "bundle", "Pacote batalha da equipe", 45000, "team",
          grants=["team_frame_ferro", "team_effect_faisca", "team_banner_bau"]),
    _item("team_pacote_gloria", "bundle", "Pacote glória da equipe", 80000, "team",
          grants=["team_frame_ouro", "team_effect_chamas", "team_name_lenda"]),
    # ---- Pass Runover (scope pass, impossíveis de comprar: só o resgate
    # da temporada concede; preço 0 nunca aparece em vitrine com filtro).
    _item("pass_banner_pioneiro", "banner", "Faixa pioneira do passe", 0, "pass",
          plate="split_neon", edge_hue=165, pulse_ms=2000,
          colors=["#3DDBB0", "#0EA5E9"]),
    _item("pass_frame_pioneiro", "frame", "Moldura pioneira do passe", 0, "pass",
          style="glass", blur=2, edge="#7DD3FC", colors=["#3DDBB0"],
          animated=False),
    _item("pass_effect_pioneiro", "effect", "Faíscas pioneiras do passe", 0, "pass",
          kind="sparkle", density=6, cycle_ms=2600, hue=140),
    _item("pass_avatar_explorador", "avatar", "Explorador do passe", 0, "pass",
          generated="adventurer", light="none", depth="flat", texture="none",
          tint="#D6FFE9", animated=False),
    _item("pass_name_capitao", "name_style", "Nome capitão do passe", 0, "pass",
          colors=["#0EA5E9"], glow=True),
    _item("pass_banner_conquistador", "banner", "Faixa conquistadora do passe", 0, "pass",
          plate="shimmer", sweep_ms=2600, colors=["#FF7F4D", "#FFC93C"]),
    _item("pass_frame_conquistador", "frame", "Moldura conquistadora do passe", 0, "pass",
          style="ring", gauge="territorio", colors=["#FF7F4D", "#FFC93C"],
          animated=False),
    _item("pass_effect_tormenta", "effect", "Tormenta do passe", 0, "pass",
          kind="storm", density=11, cycle_ms=1900, hue=270),
    _item("pass_name_lenda", "name_style", "Nome lenda do passe", 0, "pass",
          colors=["#8B7CFF", "#FFC93C"], glow=True),
]

# ---------------------------------------------------------------------------
# Expansão da biblioteca: +100 opções novas por categoria, sem repetidos.
# O catálogo continua versionado em código e 100% orientado a dados: o app
# renderiza tudo a partir do `payload` (estilo/seed da API de avatares, cores,
# emoji, kind do efeito, animação), então nenhum binário novo é necessário —
# e, porque cada item nasce de um ponto diferente do espaço de opções, nenhum
# se repete na vitrine. IDs e nomes são únicos por construção, e `_assert_unique`
# também compara a assinatura visual de cada item: repetição faz falhar no boot.
# Itens base acima são preservados com preço/ID estáveis para não quebrar
# inventários existentes nem os testes.
# ---------------------------------------------------------------------------

_EXTRA_PER_CATEGORY = 100

# Os estilos que o app conhece (`diceBearAvatarStyles`). Um estilo fora desta
# lista cai no padrão do app e a loja mostraria dois itens iguais.
_AVATAR_STYLES = (
    "adventurer", "avataaars", "bottts", "personas", "notionists", "thumbs",
    "pixel-art", "lorelei",
)
_AVATAR_THEMES = (
    "Ambar", "Aurora", "Boreal", "Ciclone", "Delta", "Eclipse", "Falcão",
    "Guepardo", "Horizonte", "Ímpeto", "Jato", "Krypton", "Litoral", "Monção",
    "Neblina", "Olimpo", "Pampa", "Quasar", "Rastro", "Sprint", "Trovão",
    "Ultramar", "Vento", "Xingu", "Zênite",
)


def _hsl(hue: int, sat: int, light: int) -> str:
    """Cor em hex a partir de um ponto da roda de matiz.

    É assim que moldura, faixa e nome ganham paleta própria sem uma tabela
    gigante: a matiz é um inteiro do índice do item, e o passo usado em cada
    gerador é coprimo com 360 — nenhum dois itens cai no mesmo ponto.
    """
    h = hue % 360 / 360
    s = sat / 100
    l = light / 100
    c = (1 - abs(2 * l - 1)) * s
    x = c * (1 - abs((h * 6) % 2 - 1))
    m = l - c / 2
    r, g, b = [(c, x, 0), (x, c, 0), (0, c, x), (0, x, c), (x, 0, c), (c, 0, x)][int(h * 6) % 6]
    return "#{:02X}{:02X}{:02X}".format(
        round((r + m) * 255), round((g + m) * 255), round((b + m) * 255)
    )


# ---------------------------------------------------------------------------
# Vocabulário visual. Cada nome abaixo é um renderizador que existe no app
# (`app/lib/widgets/cosmetics.dart`): um tipo novo aqui é um jeito novo de
# desenhar, e um tipo que o app não conhece faz `_assert_vocabulary` falhar no
# boot — a loja não pode anunciar um efeito que ela não sabe mostrar.
# ---------------------------------------------------------------------------

# Efeitos de palco. Cada tipo tem física própria: de onde sai, como se move e
# como some. `density` é o número de unidades desenhadas e `cycle_ms` é o
# tempo de um ciclo completo; `hue` dá a cor-base do tipo.
EFFECT_KINDS = (
    "sparkle",      # faíscas/glitter piscando no lugar
    "fire",         # chamas subindo da base
    "ember",        # brasas à deriva, subindo devagar
    "cold_spark",   # jato de faísca fria (CO2), cone curto e branco
    "confetti",     # chuva de confete girando
    "streamer",     # serpentina em fitas ondulantes
    "fog",          # névoa baixa rasteira (gelo seco)
    "smoke",        # fumaça densa subindo
    "color_smoke",  # explosão de fumaça colorida
    "wind",         # vento artificial atravessando o cartão
    "rain",         # chuva artificial
    "snow",         # neve artificial
    "storm",        # tempestade: chuva forte + clarão de raio
    "laser",        # laser show, feixes varrendo
    "strobe",       # luz estroboscópica pulsando o campo inteiro
    "hologram",     # varredura holográfica translúcida
    "projection",   # projeção mapeada, grade de losangos acendendo
    "lens_flare",   # reflexo de lente: halo, barra e espículas
    "orbit",        # partículas em órbita com rastro
)

# Os nomes que a vitrine mostra, na ordem de `EFFECT_KINDS`.
EFFECT_LABELS = (
    "Faíscas", "Chamas", "Brasas", "Faísca fria", "Confete", "Serpentina",
    "Névoa seca", "Fumaça", "Fumaça colorida", "Vento", "Chuva", "Neve",
    "Tempestade", "Laser", "Estroboscópio", "Holograma", "Projeção",
    "Flare", "Órbita",
)

# Molduras de avatar: nove famílias de acabamento, da interface limpa à
# ranqueada e à animada.
FRAME_STYLES = (
    "glass",    # anel de vidro fosco, borda clara fina
    "mono",     # borda monocromática finíssima, pulsa com a presença
    "geo",      # corte geométrico assimétrico com indicador chanfrado
    "metal",    # metais nobres: ornamentos conforme o patamar
    "faction",  # facção/território: fibra, pedra, runa, circuito
    "ring",     # medidor: a moldura é a barra de XP circular
    "chroma",   # neon fluido correndo em volta
    "ambient",  # partículas ambientes orbitando uma borda discreta
    "glitch",   # falha digital estática piscando
)

_METAL_GRADES = ("bronze", "prata", "ouro", "platina", "diamante")
_FRAME_ORNAMENTS = ("none", "wings", "jewel", "spikes")
_FACTION_TEXTURES = ("carbon", "stone", "rune", "circuit")
_FRAME_PARTICLES = ("leaf", "petal", "stardust", "energy")

# Os nomes que a vitrine mostra por família de moldura, na ordem de
# `FRAME_STYLES`.
_FRAME_NAMES = {
    "glass": "Vidro fosco",
    "mono": "Borda simples",
    "geo": "Corte assimétrico",
    "metal": "Metal nobre",
    "faction": "Facção",
    "ring": "Medidor",
    "chroma": "Neon fluido",
    "ambient": "Partículas",
    "glitch": "Falha digital",
}

# Acabamento do avatar: iluminação, profundidade e textura desenhadas como
# camada sobre o rosto que vem da API. Não é binário novo no pacote.
AVATAR_LIGHTS = ("rim", "back", "top", "side", "none")
AVATAR_DEPTHS = ("inner", "bevel", "flat")
AVATAR_TEXTURES = ("grain", "carbon", "brushed", "hex", "canvas", "dots", "none")
AVATAR_TINTS = (
    "#FFE9C9", "#FFD1A1", "#C9E7FF", "#E3D4FF", "#D6FFE9", "#FFD6E7",
    "#FFF3C4", "#CFD8FF",
)

# Emoticons: o pacote não é só a lista de glifos. Cada item declara como o app
# o apresenta — a profundidade da peça, o jeito como ela entra em cena, se ela
# vira distintivo no canto do avatar e se solta rastro.
EMOTICON_DEPTHS = (
    "glass",       # bolha de vidro fosco com borda fina brilhante
    "lifted",      # sombra suave em camadas: flutua sobre o cartão
    "volumetric",  # gradiente esférico, parece objeto em 3D
    "flat",        # sem tratamento (raro, só quando o glifo já basta)
)
EMOTICON_MOTIONS = (
    "spring",      # entra crescendo, estica e comprime (gelatina de iOS)
    "heartbeat",   # pulsa de tamanho e luz o tempo todo (status)
    "pop_spin",    # surge do centro com giro de poucos graus
    "float",       # sobe devagar e some, em loop
)
EMOTICON_BADGES = (
    "none",        # só o glifo no mural
    "corner",      # distintivo sobreposto ao canto inferior direito do avatar
    "ring",        # anel branco recortando a moldura, estilo status
)

# Os nomes que a vitrine mostra por movimento do pacote, na ordem de
# `EMOTICON_MOTIONS`.
_EMOTICON_PRESENTATION_NAMES = {
    "spring": "mola",
    "heartbeat": "pulso",
    "pop_spin": "giro",
    "float": "flutua",
}

# Placas de fundo (as faixas do perfil): a estrutura que segura nome e status
# embaixo do avatar. Cada estilo é um jeito de desenhar a placa — inclusive as
# que são comportamento, como a paralaxe e a borda que respira.
PLATE_STYLES = (
    "glass",      # vidro fosco com desfoque e borda milimétrica brilhante
    "gradient",   # gradiente dinâmico suave, sem linha dura
    "carbon",     # fibra de carbono fosca
    "territory",  # silhueta de mapa vetorial da região dominada
    "brushed",    # metal escovado: titânio escuro até ouro, por patamar
    "split_neon", # placa escura com LED neon pulsante numa borda
    "shimmer",    # feixe de luz varrendo a placa (cartão holográfico)
    "parallax",   # o fundo desloca contra o ponteiro: profundidade real
    "pulse",      # borda respirando devagar, sinal de perfil vivo
)

# Patamares do metal escovado: a placa muda de material conforme sobe.
PLATE_GRADES = ("titanio", "aco", "cobre", "ouro", "platina")

# O que cada família de efeito pede de física. Sem isto, um `density` 14 em
# `fog` desenharia catorze nuvens no mesmo lugar e névoa viraria borrão.
_EFFECT_PHYSICS = {
    "sparkle": (7, 16, 1800, 3200),
    "fire": (8, 18, 1200, 2200),
    "ember": (8, 20, 2200, 3800),
    "cold_spark": (12, 26, 900, 1500),
    "confetti": (14, 34, 2000, 3400),
    "streamer": (4, 10, 2600, 4200),
    "fog": (4, 9, 4200, 6400),
    "smoke": (5, 12, 3200, 5200),
    "color_smoke": (3, 8, 2400, 4000),
    "wind": (6, 14, 1600, 2800),
    "rain": (18, 46, 900, 1600),
    "snow": (14, 36, 3600, 6000),
    "storm": (16, 40, 1100, 1900),
    "laser": (4, 9, 1800, 3000),
    "strobe": (2, 6, 700, 1400),
    "hologram": (6, 14, 2000, 3200),
    "projection": (10, 26, 2200, 3600),
    "lens_flare": (3, 7, 3000, 5200),
    "orbit": (5, 12, 1800, 3400),
}


def _effect_params(kind: str, i: int) -> dict:
    """Física do tipo `kind` variando com o índice: nada cai no mesmo ponto."""
    d_lo, d_hi, c_lo, c_hi = _EFFECT_PHYSICS[kind]
    span = d_hi - d_lo
    steps = max(1, span)
    density = d_lo + (i * 7) % (steps + 1)
    cycle_ms = c_lo + (i * 173) % (c_hi - c_lo)
    return {"kind": kind, "density": density, "cycle_ms": cycle_ms, "hue": (i * 137) % 360}


# Complementos das famílias de moldura e de placa. Cada nome aqui é um desenho
# que o app conhece; fora da lista, `_assert_vocabulary` derruba o boot.
_FRAME_NOTCHES = ("top", "right", "bottom", "left", "corner_tl", "corner_br")
_FRAME_GAUGES = ("xp", "sequencia", "territorio")
_PLATE_REGIONS = (
    "Sudeste", "Sul", "Nordeste", "Norte", "Centro-Oeste", "Cerrado", "Pampa",
    "Pantanal", "Caatinga", "Litoral",
)

# Tintas vivas dos emoticons: o glifo é emoji, então a cor é do tratamento
# (brilho, halo, rastro), não da peça.
_EMOTICON_TINTS = (
    "#FFC93C", "#8B7CFF", "#3DDBB0", "#FF7F4D", "#22D3EE", "#F472B6",
    "#A3E635", "#FB7185",
)


def _frame_params(style: str, i: int) -> dict:
    """O que a família `style` desenha, variando com o índice do item.

    Uma moldura não é só a cor do anel: vidro fosco tem desfoque e borda,
    medidor tem o que ele mede, facção tem textura, metal tem patamar e
    ornamento, partícula tem do que é feito o rastro.
    """
    if style == "glass":
        return {"blur": 1 + i % 3, "edge": _hsl(i * 137, 45, 88)}
    if style == "mono":
        return {"thickness": 1 + i % 2, "pulse": i % 2 == 0}
    if style == "geo":
        return {"notch": _FRAME_NOTCHES[i % len(_FRAME_NOTCHES)]}
    if style == "metal":
        return {
            "grade": _METAL_GRADES[i % len(_METAL_GRADES)],
            "ornament": _FRAME_ORNAMENTS[(i // 5) % len(_FRAME_ORNAMENTS)],
        }
    if style == "faction":
        return {"texture": _FACTION_TEXTURES[i % len(_FACTION_TEXTURES)]}
    if style == "ring":
        return {"gauge": _FRAME_GAUGES[i % len(_FRAME_GAUGES)]}
    if style == "chroma":
        return {"speed_ms": 1600 + (i * 211) % 2400}
    if style == "ambient":
        return {
            "particle": _FRAME_PARTICLES[i % len(_FRAME_PARTICLES)],
            "count": 6 + (i * 5) % 10,
        }
    return {"jitter": 1 + i % 4, "interval_ms": 900 + (i * 173) % 1800}


def _plate_params(style: str, i: int) -> dict:
    """O que a família `plate` desenha na placa de fundo do perfil."""
    if style == "glass":
        return {"blur": 2 + i % 4, "edge": _hsl(i * 149, 40, 86)}
    if style == "gradient":
        return {"angle": (i * 37) % 180}
    if style == "carbon":
        return {"weave": 1 + i % 3}
    if style == "territory":
        return {"region": _PLATE_REGIONS[i % len(_PLATE_REGIONS)]}
    if style == "brushed":
        return {"grade": PLATE_GRADES[i % len(PLATE_GRADES)]}
    if style == "split_neon":
        return {"edge_hue": (i * 113) % 360, "pulse_ms": 1400 + (i * 191) % 1600}
    if style == "shimmer":
        return {"sweep_ms": 2200 + (i * 197) % 2600}
    if style == "parallax":
        return {"depth": 1 + i % 3}
    return {"period_ms": 1800 + (i * 151) % 1600}


def _avatar_finish(i: int) -> dict:
    """Iluminação, profundidade e textura sobre o rosto que vem da API.

    O rosto já é único pelo `seed`; o acabamento é a camada por cima — a luz
    de recorte, o canto interno escurecido, a textura fosca. Três eixos que se
    combinam por índices coprimos, então as cem galerias não repetem combinação.
    """
    return {
        "light": AVATAR_LIGHTS[i % len(AVATAR_LIGHTS)],
        "depth": AVATAR_DEPTHS[(i // 2) % len(AVATAR_DEPTHS)],
        "texture": AVATAR_TEXTURES[(i * 3) % len(AVATAR_TEXTURES)],
        "tint": AVATAR_TINTS[(i * 5) % len(AVATAR_TINTS)],
    }


def _emoticon_presentation(n: int) -> dict:
    """Material, entrada, distintivo e rastro do pacote de emoticons."""
    return {
        "depth": EMOTICON_DEPTHS[n % len(EMOTICON_DEPTHS)],
        "motion": EMOTICON_MOTIONS[(n // 2) % len(EMOTICON_MOTIONS)],
        "badge": EMOTICON_BADGES[(n // 3) % len(EMOTICON_BADGES)],
        "trail": n % 2 == 0,
        "tint": _EMOTICON_TINTS[(n * 3) % len(_EMOTICON_TINTS)],
    }


_BANNER_THEMES = (
    "Amanhecer", "Arrecife", "Asfalto", "Caatinga", "Cerrado", "Chapada",
    "Cordilheira", "Deserto", "Enseada", "Floresta", "Geleira", "Ilha",
    "Jangada", "Lagoa", "Mangue", "Maré", "Montanha", "Pantanal", "Praia",
    "Recife", "Rio", "Savana", "Serra", "Tempestade", "Vulcão",
)

_NAME_THEMES = (
    "Aço", "Âmbar", "Basalto", "Bronze", "Caramelo", "Carmesim", "Céu",
    "Cobre", "Coral", "Cristal", "Esmeralda", "Grafite", "Jade", "Lilás",
    "Magenta", "Marfim", "Menta", "Níquel", "Ônix", "Opala", "Petróleo",
    "Platina", "Rubi", "Safira", "Topázio",
)

_EMOJI_POOL = (
    "🏆", "🥇", "🥈", "🥉", "🏅", "⚡", "🔥", "💧", "🌊", "⛰️", "🏔️", "🌋",
    "🌅", "🌇", "🌈", "❄️", "💨", "🌪️", "🎯", "🚀", "🛰️", "🧭", "⌚", "👟",
    "🎽", "🚴", "🏊", "🧗", "🤸", "💪", "🦵", "❤️", "💚", "💙", "💜", "🖤",
    "⭐", "🌟", "✨", "💫", "👑",
)

_BUNDLE_THEMES = (
    "Trilha", "Velocidade", "Resistência", "Conquista", "Exploração",
    "Maratona", "Meia-maratona", "Intervalado", "Fartlek", "Longão",
    "Montanha", "Cidade", "Parque", "Praia", "Noturno", "Aurora",
    "Tempestade", "Nevoeiro", "Horizonte", "Cume", "Vale", "Rio", "Lago",
    "Floresta", "Deserto",
)


def _extra_avatars() -> list[dict]:
    """Rostos da API de avatares, cada um com o próprio acabamento.

    O estilo roda entre os que o app conhece e o `seed` é o id do item
    (`_normalize`), então cada um dos cem é uma figura diferente — foi assim
    que a biblioteca própria de PNGs saiu da loja sem a loja encolher. Sobre o
    rosto vai `_avatar_finish`: luz, profundidade, textura e matiz, que é o que
    separa "mais um boneco" de um cosmético desenhado.
    """
    items = []
    for i in range(_EXTRA_PER_CATEGORY):
        style = _AVATAR_STYLES[i % len(_AVATAR_STYLES)]
        theme = _AVATAR_THEMES[(i // len(_AVATAR_STYLES)) % len(_AVATAR_THEMES)]
        items.append(_item(
            f"avatar_galeria_{i + 1:03d}", "avatar",
            f"{theme} {i + 1:03d}",
            60 + (i * 17) % 1400,
            generated=style,
            **_avatar_finish(i),
        ))
    return items


def _extra_frames() -> list[dict]:
    """Molduras: as nove famílias de acabamento, cada uma com seus parâmetros.

    A cor continua no `colors` porque todo anel tem cor — o que muda de família
    para família é o desenho por cima dela (desfoque, ornamento, textura,
    medidor, rastro). O passo de matiz é coprimo com 360, então nenhuma das cem
    cai no mesmo ponto da roda.
    """
    items = []
    for i in range(_EXTRA_PER_CATEGORY):
        style = FRAME_STYLES[i % len(FRAME_STYLES)]
        hue = i * 137
        colors = [_hsl(hue, 78, 55)]
        if i % 2:
            colors.append(_hsl(hue + 42, 78, 48))
        items.append(_item(
            f"frame_colecao_{i + 1:03d}", "frame",
            f"{_FRAME_NAMES[style]} {i + 1:03d}",
            90 + (i * 23) % 1500,
            style=style,
            colors=colors,
            **_frame_params(style, i),
        ))
    return items


def _extra_effects() -> list[dict]:
    """Efeitos de palco: os dezenove tipos, cada um com sua física.

    `kind` escolhe o desenho, `density`/`cycle_ms`/`hue` vêm de `_effect_params`
    dentro da faixa que o tipo suporta — névoa com densidade de chuva é borrão,
    e é por isso que a faixa é por tipo, não global.
    """
    items = []
    for i in range(_EXTRA_PER_CATEGORY):
        index = i % len(EFFECT_KINDS)
        kind = EFFECT_KINDS[index]
        items.append(_item(
            f"effect_inedito_{i + 1:03d}", "effect",
            f"{EFFECT_LABELS[index]} {i + 1:03d}",
            120 + (i * 29) % 1500,
            **_effect_params(kind, i),
        ))
    return items


def _extra_banners() -> list[dict]:
    """Placas de fundo: os nove estilos de estrutura por baixo do nome.

    A faixa continua com `colors` (é o gradiente da placa), e `plate` diz de que
    jeito ela é desenhada — vidro, metal escovado com patamar, mapa do
    território, varredura, paralaxe ou borda que respira.
    """
    items = []
    for i in range(_EXTRA_PER_CATEGORY):
        theme = _BANNER_THEMES[i % len(_BANNER_THEMES)]
        plate = PLATE_STYLES[i % len(PLATE_STYLES)]
        hue = 61 + i * 149  # coprimo com 360, e deslocado das molduras
        items.append(_item(
            f"banner_paisagem_{i + 1:03d}", "banner",
            f"{theme} {i + 1:03d}",
            110 + (i * 19) % 1400,
            plate=plate,
            colors=[
                _hsl(hue, 74, 52),
                _hsl(hue + 38, 74, 40),
                _hsl(hue + 76, 60, 28),
            ],
            **_plate_params(plate, i),
        ))
    return items


def _extra_name_styles() -> list[dict]:
    items = []
    for i in range(_EXTRA_PER_CATEGORY):
        theme = _NAME_THEMES[i % len(_NAME_THEMES)]
        hue = 173 + i * 131  # coprimo com 360
        items.append(_item(
            f"name_estilo_{i + 1:03d}", "name_style",
            f"Nome {theme.lower()} {i + 1:03d}",
            130 + (i * 21) % 1400,
            colors=[_hsl(hue, 82, 58), _hsl(hue + 30, 82, 46)],
            glow=i % 2 == 0,
        ))
    return items


def _extra_emoticons() -> list[dict]:
    items = []
    # Os combos dos itens base já estão na vitrine; deixá-los de fora é o que
    # impede dois pacotes com os mesmos emojis na mesma categoria.
    used: set[tuple] = {
        tuple(sorted(item["payload"].get("emoji") or ()))
        for item in CATALOG_BASE
        if item["category"] == "emoticon"
    }
    i = 0
    n = 0
    while n < _EXTRA_PER_CATEGORY:
        size = 1 + (i % 3)
        combo = tuple(sorted(
            _EMOJI_POOL[(i * 7 + k * 13) % len(_EMOJI_POOL)] for k in range(size)
        ))
        i += 1
        if combo in used:
            continue
        used.add(combo)
        n += 1
        presentation = _emoticon_presentation(n)
        items.append(_item(
            f"emoticon_pacote_{n:03d}", "emoticon",
            f"Pacote {_EMOTICON_PRESENTATION_NAMES[presentation['motion']]} {n:03d}",
            80 + ((n * 31) % 900),
            emoji=list(combo),
            **presentation,
        ))
    return items


def _extra_bundles() -> list[dict]:
    """Pacotes: três itens da loja pessoal por preço menor, com capa própria.

    O `colors` é a capa do cartão na vitrine — sem ela, cem pacotes desenhariam
    o mesmo degradê e a diferença entre eles sumiria antes do toque.
    """
    items = []
    for i in range(_EXTRA_PER_CATEGORY):
        theme = _BUNDLE_THEMES[i % len(_BUNDLE_THEMES)]
        a = 1 + ((i * 3) % _EXTRA_PER_CATEGORY)
        f = 1 + ((i * 5 + 1) % _EXTRA_PER_CATEGORY)
        b = 1 + ((i * 7 + 2) % _EXTRA_PER_CATEGORY)
        grants = [f"avatar_galeria_{a:03d}", f"frame_colecao_{f:03d}", f"banner_paisagem_{b:03d}"]
        prices = (
            60 + ((a - 1) * 17) % 1400,
            90 + ((f - 1) * 23) % 1500,
            110 + ((b - 1) * 19) % 1400,
        )
        price = max(200, round(sum(prices) * 0.8))
        hue = 29 + i * 149  # coprimo com 360: nenhuma capa repete o ponto
        items.append(_item(
            f"pacote_trilha_{i + 1:03d}", "bundle",
            f"Pacote {theme.lower()} {i + 1:03d}",
            price,
            grants=grants,
            colors=[_hsl(hue, 70, 46), _hsl(hue + 44, 70, 30)],
        ))
    return items


def _plain(value):
    """Versão comparável de um valor de payload (lista, bool, str, número)."""
    if isinstance(value, dict):
        return tuple(sorted((key, _plain(item)) for key, item in value.items()))
    if isinstance(value, (list, tuple)):
        return tuple(_plain(item) for item in value)
    return value


# O que não muda o desenho: a política de "tudo animado", o degrau da escada de
# animação e a coleção da vitrine. Nada mais pode ficar fora da assinatura.
_NOT_VISUAL = frozenset({"animated", "tier", "collection"})


def _signature(item: dict) -> tuple:
    """O payload visual inteiro, congelado.

    Dois itens com a mesma assinatura são o mesmo item duas vezes na vitrine —
    é isto que a loja não pode ter, e não apenas ids e nomes distintos. Por isso
    a conta pega cada chave do payload menos `_NOT_VISUAL`: cor, tipo de efeito,
    família de moldura, parâmetro da placa, acabamento do avatar. Nome diferente
    com payload igual é exatamente a repetição que a loja tinha.

    O escopo entra na conta porque cada loja se mostra sozinha: a moldura da
    equipe e a pessoal com o mesmo desenho não se repetem na mesma tela.
    """
    payload = item["payload"]
    visual = tuple(
        sorted((key, _plain(value)) for key, value in payload.items()
               if key not in _NOT_VISUAL)
    )
    return (item.get("scope", "user"), item["category"], visual)


# Fecha o vocabulário: cada chave de payload que nomeia um renderizador do app
# só aceita os valores desta tabela. Um nome escrito errado aqui seria um item
# que a loja anuncia e o app não sabe desenhar — por isto o boot falha.
_VOCABULARIES: dict[tuple[str, str], tuple[str, ...]] = {
    ("effect", "kind"): EFFECT_KINDS,
    ("frame", "style"): FRAME_STYLES,
    ("frame", "grade"): _METAL_GRADES,
    ("frame", "ornament"): _FRAME_ORNAMENTS,
    ("frame", "texture"): _FACTION_TEXTURES,
    ("frame", "notch"): _FRAME_NOTCHES,
    ("frame", "gauge"): _FRAME_GAUGES,
    ("frame", "particle"): _FRAME_PARTICLES,
    ("avatar", "light"): AVATAR_LIGHTS,
    ("avatar", "depth"): AVATAR_DEPTHS,
    ("avatar", "texture"): AVATAR_TEXTURES,
    ("banner", "plate"): PLATE_STYLES,
    ("banner", "grade"): PLATE_GRADES,
    ("banner", "region"): _PLATE_REGIONS,
    ("emoticon", "depth"): EMOTICON_DEPTHS,
    ("emoticon", "motion"): EMOTICON_MOTIONS,
    ("emoticon", "badge"): EMOTICON_BADGES,
}


def _assert_vocabulary(catalog: list[dict]) -> None:
    problems = []
    for entry in catalog:
        category = entry["category"]
        for key, value in entry["payload"].items():
            allowed = _VOCABULARIES.get((category, key))
            if allowed is None or not isinstance(value, str):
                continue
            if value not in allowed:
                problems.append(f"{entry['id']}: {category}.{key}={value!r}")
    if problems:
        raise ValueError(
            "Vocabulário visual fora das opções do app: "
            + ", ".join(sorted(problems))
        )


def _assert_unique(catalog: list[dict]) -> None:
    ids = [i["id"] for i in catalog]
    names = [(i["category"], i["name"]) for i in catalog]
    signatures = [_signature(i) for i in catalog]
    dup_ids = sorted({v for v in ids if ids.count(v) > 1})
    dup_names = sorted({v for v in names if names.count(v) > 1})
    dup_sigs = sorted({str(v) for v in signatures if signatures.count(v) > 1})
    if dup_ids or dup_names or dup_sigs:
        raise ValueError(
            "Catálogo com repetidos: "
            f"ids={dup_ids} nomes={dup_names} visuais={dup_sigs}"
        )


CATALOG: list[dict] = (
    list(CATALOG_BASE)
    + _extra_avatars()
    + _extra_frames()
    + _extra_effects()
    + _extra_banners()
    + _extra_name_styles()
    + _extra_emoticons()
    + _extra_bundles()
)


def _normalize(catalog: list[dict]) -> None:
    """Regras que valem para o catálogo inteiro, aplicadas uma vez no boot.

    - Avatar da API: o `seed` é o id do item. A figura é do cosmético, não de
      quem o equipou, então a vitrine, o perfil e o cartão de ranking mostram o
      mesmo rosto para o mesmo item.
    - Política da loja: nada estático — todo item nasce animado.
    - `tier` de 1 a 4 é a escada de animação: quanto mais alto o tipo, mais
      movimento. O nível é o preço relativo dentro do próprio escopo e
      categoria, porque a loja da equipe conta em pontos e uma moldura de
      5.000 pontos não é "mais cara" que uma de 500 dracmas.
    """
    for entry in catalog:
        payload = entry["payload"]
        if entry["category"] == "avatar" and payload.get("generated"):
            payload.setdefault("seed", entry["id"])
        payload["animated"] = True

    groups: dict[tuple[str, str], list[dict]] = {}
    for entry in catalog:
        groups.setdefault(
            (entry.get("scope", "user"), entry["category"]), []
        ).append(entry)
    for group in groups.values():
        ordered = sorted(group, key=lambda item: (item["price"], item["id"]))
        total = len(ordered)
        for index, entry in enumerate(ordered):
            entry["payload"]["tier"] = min(4, 1 + index * 4 // total)


_normalize(CATALOG)
_assert_vocabulary(CATALOG)
_assert_unique(CATALOG)

BY_ID = {item["id"]: item for item in CATALOG}


def get_item(item_id: str) -> dict | None:
    return BY_ID.get(item_id)


def list_items(category: str | None = None, scope: str | None = None) -> list[dict]:
    items = CATALOG
    if scope is not None:
        items = [i for i in items if i.get("scope", "user") == scope]
    if category is None:
        return list(items)
    return [i for i in items if i["category"] == category]


def team_items() -> list[dict]:
    """Catálogo da loja da equipe (escopo team, valores altos)."""
    return [i for i in CATALOG if i.get("scope") == "team"]


def free_items() -> list[dict]:
    return [i for i in CATALOG if i["price"] == 0]

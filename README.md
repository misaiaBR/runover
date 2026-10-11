# RUNOVER!

Aplicativo Flutter para registrar corridas, acompanhar progresso e disputar territórios por geolocalização. O Flutter Web e a API FastAPI são servidos pelo mesmo serviço Render em `https://runover.onrender.com`.

## Tecnologias

- Flutter 3.47.2 e Dart 3.13.2 para Android e Web.
- FastAPI, Pydantic e SQLAlchemy no backend.
- PostgreSQL do Neon em produção; SQLite em desenvolvimento e testes.
- Shapely para geometria; `flutter_map` e OpenStreetMap para mapas.
- SharedPreferences para sessão e rascunhos de corrida separados por conta.

O backend está em `backend/app/`; as telas, serviços e testes Flutter estão em `app/lib/` e `app/test/`. `backend/app/geometry.py` calcula e valida as áreas; `backend/app/routers/` contém as rotas da API.

## Executar localmente

Requisitos: Python 3.12.10, Flutter 3.47.2, Dart 3.13.2 e, para Android, JDK 17 e Android SDK.

Use o FVM para travar o SDK na versão do projeto (ver `.fvmrc`):

```powershell
dart pub global activate fvm
fvm install
fvm flutter --version
```

Daí em diante, troque `flutter` por `fvm flutter` nos comandos (`fvm flutter pub get`, `fvm flutter test`, ...). Sem FVM, confira com `flutter --version` antes de rodar — análise, testes e build exigem a versão requisitada.

No PowerShell, a partir da raiz:

```powershell
py -3.12 -m venv backend\.venv
backend\.venv\Scripts\python.exe -m pip install -r backend\requirements-dev.txt
Set-Location backend
$env:CORS_ALLOWED_ORIGINS = "https://runover.onrender.com,http://localhost:8080"
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Em outro terminal:

```powershell
Set-Location app
flutter pub get --enforce-lockfile
flutter run -d chrome --web-port 8080 --dart-define=API_BASE=http://127.0.0.1:8000
```

Para permitir a origem local no navegador, inicie o backend com `$env:CORS_ALLOWED_ORIGINS="https://runover.onrender.com,http://localhost:8080"` antes do Uvicorn. Em produção, o Render usa somente a origem Web publicada; adicione qualquer domínio customizado em `CORS_ALLOWED_ORIGINS` no painel e em `render.yaml`.

A API local fica em `http://127.0.0.1:8000`; `/health` verifica sua disponibilidade. Para Android Emulator, use `http://10.0.2.2:8000` como `API_BASE`. Em um aparelho físico, use um endereço IP acessível pela rede local.

## Testes e build

Na raiz do repositório:

```powershell
$env:PYTHONPATH = "backend"
backend\.venv\Scripts\python.exe -m unittest discover -s backend/tests -v
backend\.venv\Scripts\python.exe -m pytest backend/tests/test_password_reset.py backend/tests/test_claim_integrity.py -q
```

Na pasta `app/`:

```powershell
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build web --release `
  --dart-define=API_BASE=https://runover.onrender.com `
  --dart-define=GOOGLE_WEB_CLIENT_ID=346362177621-g8li6h47ic6sot55p68700a0lgpqo01v.apps.googleusercontent.com `
  --dart-define=GOOGLE_SERVER_CLIENT_ID=346362177621-g8li6h47ic6sot55p68700a0lgpqo01v.apps.googleusercontent.com
flutter build apk --release --dart-define=API_BASE=https://runover.onrender.com
```

O CI executa o scan de segredos, as suítes backend com SQLite e PostgreSQL, análise e testes Flutter, e builds release-mode para Web e Android. O build Web usa as mesmas definições públicas de produção do Docker. O APK de CI usa assinatura de debug e serve somente como verificação de compilação; não o distribua. Os testes usam dados descartáveis; não configure o Neon de produção como banco de teste.

A API tem collection executável do Postman em `backend/tests/postman/` (`runover-api.postman_collection.json` + ambientes local/CI). Para rodar local com Newman, suba a API e execute:

```powershell
newman run backend/tests/postman/runover-api.postman_collection.json -e backend/tests/postman/runover-local.postman_environment.json
```

O fluxo usa banco limpo (cadastra, encadeia o token, termina excluindo a conta). Para publicar a documentação estilo documenter, importe a collection no Postman e use View Documentation → Publish.

## Regras e dados

Uma corrida aceita até 10.000 pontos, dura de 1 segundo a 6 horas, precisa registrar pelo menos 10 metros e deve ser enviada em até 7 dias. Coordenadas devem ser válidas, horários crescentes com fuso informado e velocidade plausível. O limite de velocidade é 8,3 m/s. A precisão vem do GPS do aparelho (o app mostra a margem de cada leitura e busca a melhor em até 15 segundos); no navegador a posição vem do próprio navegador (WiFi/rede) e pode variar centenas de metros.

Para conquistar, o percurso precisa fechar um laço dentro de 30 metros do início e formar uma área entre 100 m² e 25 km². Uma corrida pausada pode ser salva, mas trechos separados não conquistam território. A posse e a pontuação mantêm histórico; o percurso completo continua privado, enquanto a área conquistada aparece no mapa.

Retomar um território é um desafio de ritmo ou distância, escolhido antes de correr: no de ritmo, o laço precisa ter ritmo médio mais rápido que o do dono; no de distância, o rival corre mais quilômetros que o dono em tempo igual ou menor. Empate não vence, e a derrota salva a corrida sem pontos e sem trocar o dono. A ficha do território mostra as marcas a bater — ritmo em min/km e a distância com o tempo máximo. Territórios antigos sem marca valem pela sobreposição do laço, até a primeira conquista que registrar marca.

Territórios selvagens aparecem sozinhos no mapa: cada área gera até 2 por hora, com raridade comum, rara ou épica (mais pontos). Todos veem os mesmos; quem fechar um laço cobrindo o centro primeiro fica com a área. Nascem grudados em ruas e calçadas (dados do OpenStreetMap) ou onde já se correu, e somem ao fim da hora ou quando conquistados.

O envio usa identificadores estáveis para que uma repetição da mesma corrida não duplique pontuação. Reutilizar um identificador com conteúdo diferente resulta em conflito. Rascunhos enfileirados ficam no aparelho, separados por conta; limpar os dados do app ou navegador remove rascunhos ainda não enviados.

A recuperação envia um código de 12 dígitos, armazena somente seu hash, expira em 30 minutos e invalida o código após cinco tentativas incorretas. Solicitações têm intervalo mínimo de 60 segundos. A resposta é genérica para não revelar se a conta existe. Redefinir a senha invalida sessões anteriores. Conta desativada volta no próximo login, com confirmação ("Reativar conta?"), por senha (`POST /auth/reactivate`) ou login social (`POST /auth/oauth/{provider}/reactivate`, só com vínculo existente).

A inicialização do backend cria tabelas de forma aditiva e não apaga dados existentes. Faça backup do Neon antes de atualizar. Corridas antigas não podem ser reconstruídas a partir de conquistas que não armazenaram o percurso. Mudanças em tabelas existentes (colunas, índices) entram em revisões Alembic (`backend/alembic/versions/`), aplicadas automaticamente na inicialização; crie uma com `alembic revision --autogenerate -m ...` a partir da pasta `backend/`.

## Render e Neon

A branch de produção é `main`. O Blueprint em `render.yaml` descreve um serviço Docker chamado `runover`, com build no `Dockerfile` da raiz e health check em `/health`. O container compila o Flutter Web e o FastAPI serve a aplicação na raiz e mantém os endpoints da API no mesmo domínio.

`DATABASE_URL` é uma variável secreta (`sync: false`) do serviço Render e deve conter a conexão do Neon. O Blueprint não cria nem substitui o banco. Preserve esse valor ao sincronizar a configuração. `SECRET_KEY` deve ser um segredo forte no ambiente de produção.

A recuperação de senha por código usa a API Brevo (HTTPS — SMTP direto nas portas 25/465/587 é bloqueado no plano gratuito do Render). Configure `BREVO_API_KEY` e `MAIL_FROM_EMAIL` no Render; `MAIL_FROM_NAME` pode permanecer como `RUNOVER!`. Nunca coloque credenciais neste arquivo ou no Git. Sem essas duas variáveis, o endpoint responde como se tivesse enviado, mas nenhum e-mail sai — esse é o sintoma de "não recebi o código". A inicialização registra um aviso no log quando o envio está desconfigurado.

O remetente precisa estar verificado na Brevo (`Senders & IP`) — vale endereço individual, sem domínio próprio. Com remetente freemail (ex.: Gmail), a Brevo reescreve o `From` para um subdomínio `brevosend.com` dela e o e-mail tem mais chance de ir ao spam — o código chega, mas com esse endereço. Para exibir `contato@seudominio` com DKIM alinhado, verifique um domínio próprio em `Domains`.

Após um deploy saudável, `https://runover.onrender.com/` abre o app e `https://runover.onrender.com/health` retorna o status da API. Todo PR compila o Dockerfile no job `docker` para não descobrir quebra só no deploy; na `main`, o job ainda dispara o Deploy Hook do Render se o segredo `RENDER_DEPLOY_HOOK` existir (senão, vale o auto-deploy do Blueprint).

### Keep-alive no plano gratuito

O serviço Render do plano gratuito é encerrado após 15 minutos sem requisições. Na primeira visita depois disso, o app responde pela tela de carregamento do Render enquanto a instância volta a subir, e a retomada após o spin-down pode levar cerca de um minuto. Um job que faz `GET` em `/health` a cada 10 minutos reduz cold starts causados por inatividade, sem garantir latência ou disponibilidade: serviços gratuitos ainda podem reiniciar por outros motivos.

O job está no [cron-job.org](https://cron-job.org/en/), sem custo e sem cartão:

| Campo | Valor |
| --- | --- |
| URL | `https://runover.onrender.com/health` |
| Método | `GET` |
| `minutes` | `0,10,20,30,40,50` |
| `hours` | todos, ou `-1` |
| Fuso | `America/Sao_Paulo` |

Use `/health` e não a raiz `/`: o endpoint devolve um objeto estático sem tocar no banco (`backend/app/main.py`), enquanto `/` entrega o bundle do Flutter Web inteiro. O intervalo mínimo do cron-job.org é de um minuto, então 10 minutos está folgado.

Prefira 10 minutos, e não 14: o cron-job.org não garante pontualidade em horário de pico, e um atraso somado à janela de 15 minutos derruba o serviço. Ative a notificação por e-mail do job — o serviço desativa tarefas automaticamente após 25 falhas consecutivas, e sem o aviso o problema só apareceria quando o app voltasse a dormir. Acompanhe o histórico de execuções e confirme `200` com `{"status":"ok","app":"RUNOVER! API"}`. Se aparecer `502` ou `503`, confira o histórico de execuções do job e os logs do serviço para identificar a causa antes de alterar o intervalo.

Isso mantém o serviço fora do encerramento de propósito, que é o mecanismo que torna o plano gratuito gratuito. Os termos da Render não proíbem pings, mas o consumo é dos recursos que o plano existe para limitar, e a política pode mudar. Latência previsível sem esse custo exige um plano pago.

## Corridas e territórios

As corridas são privadas; ao optar por conquistar, a área formada é publicada no mapa. Corridas pendentes permanecem no aparelho e são reenviadas com o mesmo identificador para evitar duplicação. `POST /runs` é o fluxo atual; o endpoint antigo `POST /territories/claim` retorna 410.

A API valida coordenadas, fusos horários, sequência dos pontos, velocidade, distância, duração e idade da corrida. Para conquistar, o percurso precisa formar um laço fechado válido com área entre 100 m² e 25 km². Percursos pausados podem ser salvos, mas trechos separados não formam uma conquista contínua.

Histórico de posse e pontuação é preservado. A inicialização do backend cria tabelas de forma aditiva; ainda assim, faça backup do Neon antes de atualizar. Não há migração automática de corridas antigas que nunca tiveram o percurso armazenado.

`POST /runs` aceita `challenge: "pace" | "distance"` junto com `conquer: true`. Na resposta, `claim.challenge_won` traz o resultado do desafio e `claim.beaten_*` a marca vencida; territórios novos não têm desafio (`challenge_won: null`) e já registram a marca do primeiro dono. `GET /territories/{id}` devolve as marcas do dono (`owner_pace_seconds_per_km`, `owner_distance_m`, `owner_duration_seconds`), e `GET /territories/nearby?lat=&lng=&radius_km=` lista os territórios cujo centro está a até `radius_km` de um ponto, com pré-filtro indexado pelo centroide (`center_lat`/`center_lng`). `GET /territories/wild?lat=&lng=&radius_km=` lista os selvagens ao redor (chave, centro, raio, raridade e expiração). A tela de corrida mostra as marcas dos rivais por perto ao ativar a conquista, para escolher o desafio antes de correr.

Os desafios do dia são sorteados por conta: dois do pool mais um longão pessoal calculado da média semanal, trocando a cada 24 horas no fuso local do jogador (`app/lib/services/daily_challenges.dart`). A aba Desafios mostra os atuais, o progresso e o tempo restante para a troca.

Cada território conta quantas vezes trocou de dono (`takeovers`); a ficha mostra o histórico de donos anteriores e o mapa colore as áreas mais disputadas, com calor calculado de retomadas e donos vizinhos (`app/lib/widgets/territory_style.dart`).

## Conta e aplicativo

Na primeira abertura após o login, um tour guiado destaca onde clicar (menu, iniciar corrida e abas), com botão Pular sempre visível; a escolha fica salva no aparelho. O menu lateral (ícone no topo da página principal) alterna as abas e dá acesso a configurações, termos, replay do tutorial ("Ver tutorial") e saída. A página principal mostra os modos de jogo em cartões horizontais: Dominação (ativo, abre o mapa), Desafio de velocidade e Pit stop de equipe.

Entrar em equipe é por pedido: o dono e os admins aprovam ou recusam em "Pedidos de entrada", com aviso por notificação. Só o dono promove e remove admins (`POST/DELETE /teams/{id}/admins`), e pode haver vários admins. Quem sai da equipe perde o cargo de admin. O dono com membros que sai escolhe o sucessor ou dissolve a equipe (`POST /teams/leave` com `successor_username` ou `dissolve`); sem escolha, a saída é recusada. Quem tem equipe pode ver as outras em "Ver outras equipes", mas só entra em outra após sair da atual. Nas configurações da equipe (dono/admin), dá para trocar foto e nome, gerenciar convites e dissolver a equipe — dissolver libera os territórios e avisa os membros. A Loja da equipe vende decoração, molduras, efeitos, faixas e nomes com valores altos em pontos, pagos com o cofre (soma dos pontos dos integrantes menos o já gasto — ninguém perde nível, ranking ou moedas); só dono/admins compram e equipam (`GET/POST /teams/{id}/wallet|inventory|purchase|equip`).

A foto de perfil aceita arquivo do dispositivo, link https ou avatares da galeria ("Avatares"); o envio de foto usa data URI de até 400 KB (JPG, PNG ou WebP), com redimensionamento feito no app. Os avatares da galeria (prontos e gerados) são itens da loja: tocar compra e equipa — tudo custa moedas do jogo, sem itens grátis. O perfil mostra pronomes, emoticons sob o nome, a faixa como fundo do cartão de identidade e a cor de destaque gratuita (vale no nome e na faixa sem cosmético); o mural exibe só as conquistas, abaixo da evolução. O ranking e a lista de equipes refletem foto, moldura, nome e faixa equipados. O Pass Runover é a temporada mensal movida a XP: 30 tiers, trilhas gratuita e premium (desbloqueio único em moedas), recompensas em moedas e cosméticos exclusivos — o não resgatado expira na virada (`GET/POST /pass`, `/pass/premium`, `/pass/claim`). Em "Editar perfil › Segurança › Excluir conta", após confirmação em duas etapas, a API (`DELETE /users/me`) apaga dados pessoais, libera territórios e invalida sessões — é preciso sair da equipe antes. Em "Privacidade › Baixar meus dados", a API (`GET /users/me/export`) devolve tudo em JSON para portabilidade (LGPD). O banner de cookies aparece na primeira abertura; "Gerenciar Cookies" no rodapé reabre as preferências.

## Android

Para gerar um APK local, use uma URL acessível pelo dispositivo:

```powershell
flutter build apk --release --dart-define=API_BASE=https://runover.onrender.com
```

Para usar HTTP em um backend local, execute o app em modo debug/profile; o manifesto só permite tráfego HTTP nesses modos. O build release local usa a chave de upload somente quando `app/android/key.properties` contém todos os campos válidos e o arquivo do keystore existe. Se o arquivo estiver ausente ou incompleto, o Gradle usa a chave debug; verifique a assinatura do APK antes de distribuí-lo. Para publicar no GitHub, crie e envie uma tag `android-vMAJOR.MINOR.PATCH`; o workflow gera o APK assinado e abre uma GitHub Release Android independente.

Com depuração USB habilitada, instale o APK com `adb install -r build/app/outputs/flutter-apk/app-release.apk`. Mantenha o app aberto durante a gravação; rastreamento contínuo em segundo plano não é garantido nesta versão.

## Documentação inicial

Documento de referência inicial do aplicativo: [abrir no Google Docs](https://docs.google.com/document/d/1-6maJZIuE-j8t6kqlTTZ05SvqkOv7emuy3gvaznPgHs/edit?usp=sharing). O conteúdo permanece no documento original; este link foi registrado aqui para consulta.

## Atualização deste guia

Este README é a documentação única do repositório. Atualize as seções correspondentes sempre que mudar setup, contratos da API, regras de corrida, banco, testes ou deploy; não crie outros arquivos Markdown para esses tópicos.

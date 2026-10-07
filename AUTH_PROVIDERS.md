# Configurar login Google e Apple

Os botões usam o backend do RUNOVER para verificar os tokens e abrir uma sessão da API. Nenhum segredo OAuth é guardado no app ou no Git.

## Google

1. No Google Cloud Console, crie credenciais OAuth para Web e Android.
2. Para Android, informe o identificador do app `com.runover.runover_app` e a impressão SHA-1 do certificado de desenvolvimento e do certificado de publicação.
3. Em **Render → serviço runover → Environment**, defina `GOOGLE_OAUTH_CLIENT_IDS` com os IDs de cliente aceitos pelo backend, separados por vírgula. Inclua o ID Web usado como server client ID.
4. Ao compilar o Flutter, passe os IDs públicos:
   - `--dart-define=GOOGLE_WEB_CLIENT_ID=<ID_WEB>`
   - `--dart-define=GOOGLE_SERVER_CLIENT_ID=<ID_WEB>`

O Google para Web mostra o botão oficial do SDK. Na Web, cadastre o endereço HTTPS do site como origem autorizada no Google Cloud.

Configurado em produção: ID Web `346362177621-g8li6h47ic6sot55p68700a0lgpqo01v.apps.googleusercontent.com` (Dockerfile + `GOOGLE_OAUTH_CLIENT_IDS` no Render). Cliente Android ainda pendente.

## Apple

O Sign in with Apple exige uma conta ativa do Apple Developer Program. No portal Apple, habilite essa capacidade e crie um **Service ID**. Para Android e Web, cadastre o domínio HTTPS do app e o retorno:

`https://runover.onrender.com/auth/apple/callback`

Em **Render → serviço runover → Environment**, defina `APPLE_OAUTH_CLIENT_IDS` com o Service ID. Na compilação Flutter, passe:

- `--dart-define=APPLE_SERVICE_ID=<SERVICE_ID>`
- `--dart-define=APPLE_REDIRECT_URI=https://runover.onrender.com/auth/apple/callback`

Para Web, o domínio que hospeda o Flutter Web também precisa estar listado no Service ID como domínio e URL de retorno. O endereço `runover.onrender.com` só vale se esse for realmente o endereço usado pelo app.

## Contas já existentes

O backend não vincula uma conta social a uma conta antiga só porque os endereços de e-mail coincidem. Isso evita que o provedor social dê acesso a uma conta de senha sem comprovar as duas identidades. O vínculo manual pode ser adicionado depois com confirmação da sessão existente.

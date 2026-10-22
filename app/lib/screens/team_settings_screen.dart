import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../widgets/avatar_shop_sheet.dart';
import '../widgets/centered_content.dart';
import '../widgets/cosmetics.dart';
import '../widgets/team_exit.dart';
import 'team_shop_screen.dart';

/// Miolo da tela de ajustes: duas colunas em janela larga, uma estreita no
/// celular.
const double kTeamSettingsMaxWidth = 1000;

/// Modos de quem pode entrar na equipe. O `apiValue` é a string do servidor.
enum JoinMode {
  approval('Por aprovação', 'Quem pedir entrada espera você aceitar', 'approval'),
  open('Aberta', 'Qualquer pessoa entra na hora', 'open'),
  inviteOnly('Só por convite', 'Entra quem tiver o seu link', 'invite_only');

  const JoinMode(this.title, this.subtitle, this.apiValue);
  final String title, subtitle, apiValue;

  static JoinMode fromApi(String raw) => values.firstWhere(
    (m) => m.apiValue == raw,
    orElse: () => approval,
  );
}

/// Estado editável do formulário (nome, entrada, listagem e avisos).
/// Imutável: cada mudança gera uma cópia nova, o que permite saber se há
/// alterações comparando com a última versão salva.
@immutable
class TeamSettings {
  const TeamSettings({
    required this.name,
    this.joinMode = JoinMode.approval,
    this.listed = true,
    this.notifyRisk = true,
    this.notifyRequests = true,
  });

  factory TeamSettings.of(TeamDetail team) => TeamSettings(
    name: team.name,
    joinMode: JoinMode.fromApi(team.joinMode),
    listed: team.listed,
    notifyRisk: team.notifyRisk,
    notifyRequests: team.notifyRequests,
  );

  final String name;
  final JoinMode joinMode;
  final bool listed, notifyRisk, notifyRequests;

  TeamSettings copyWith({
    String? name,
    JoinMode? joinMode,
    bool? listed,
    bool? notifyRisk,
    bool? notifyRequests,
  }) => TeamSettings(
    name: name ?? this.name,
    joinMode: joinMode ?? this.joinMode,
    listed: listed ?? this.listed,
    notifyRisk: notifyRisk ?? this.notifyRisk,
    notifyRequests: notifyRequests ?? this.notifyRequests,
  );

  @override
  bool operator ==(Object other) =>
      other is TeamSettings &&
      other.name == name &&
      other.joinMode == joinMode &&
      other.listed == listed &&
      other.notifyRisk == notifyRisk &&
      other.notifyRequests == notifyRequests;

  @override
  int get hashCode =>
      Object.hash(name, joinMode, listed, notifyRisk, notifyRequests);
}

/// Configurações da equipe — a única superfície de ajustes do time.
///
/// O conteúdo muda com o papel de quem abre, porque o servidor também muda:
/// dono e admin editam entrada, convites, avisos e nome; membro sem cargo vê
/// esses dados e só pode sair. O emblema não é campo daqui: ele é item da Loja
/// da equipe, e esta tela só abre a folha que compra e equipa. Dissolver é
/// exclusivo do dono.
class TeamSettingsScreen extends StatefulWidget {
  const TeamSettingsScreen({
    super.key,
    required this.team,
    required this.onChanged,
  });

  final TeamDetail team;
  final VoidCallback onChanged;

  @override
  State<TeamSettingsScreen> createState() => _TeamSettingsScreenState();
}

class _TeamSettingsScreenState extends State<TeamSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late TeamSettings _baseline; // última versão salva no servidor
  late TeamSettings _s; // versão em edição
  late List<TeamJoinRequestInfo> _requests;
  late String? _inviteLink;

  /// O emblema é item da Loja da equipe, não campo de foto: a prévia precisa do
  /// item equipado para desenhar o mesmo rosto que o painel desenha. O id vem da
  /// equipe ao abrir e do inventário da equipe depois de cada compra.
  late String? _emblemId;
  List<ShopItem> _emblems = const [];

  bool _saving = false;
  bool _busy = false;

  bool get _isAdmin => widget.team.isAdmin;
  bool get _isOwner => widget.team.isOwner;
  bool get _dirty => _s != _baseline;

  ShopItem? get _emblem => findItem(_emblems, _emblemId);

  @override
  void initState() {
    super.initState();
    _baseline = TeamSettings.of(widget.team);
    _s = _baseline;
    _requests = List.of(widget.team.pendingRequests);
    _inviteLink = _linkOf(widget.team.inviteToken);
    _emblemId = widget.team.equippedAvatar;
    _name = TextEditingController(text: _s.name);
    _loadEmblems();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  static String? _linkOf(String? token) =>
      token == null || token.isEmpty ? null : '/teams/join/$token';

  /// Catálogo de emblemas + o que a equipe tem equipado hoje.
  ///
  /// A leitura não vaza erro para a tela: sem ela a prévia fica na foto ou na
  /// letra inicial — o mesmo que uma equipe sem emblema mostra — e a folha da
  /// loja, que é o controle de verdade, carrega o catálogo dela própria e tem
  /// botão de retry.
  Future<void> _loadEmblems() async {
    final api = context.read<AppState>().api;
    final teamId = widget.team.id;
    try {
      final results = await Future.wait([
        api.getShopCatalog(scope: 'team', category: 'avatar'),
        api.getTeamInventory(teamId),
      ]);
      if (!mounted) return;
      setState(() {
        _emblems = results[0] as List<ShopItem>;
        _emblemId = (results[1] as TeamInventory).equippedAvatar;
      });
    } catch (_) {
      // Sem catálogo nada muda: a prévia cai no rosto que a equipe já tinha.
    }
  }

  /// Voltou da Loja da equipe — pela folha do emblema ou pela rota da loja
  /// inteira. Quem compra ou equipa por lá muda as duas coisas que esta tela
  /// mostra, e nenhuma das duas rotas se atualiza sozinha: a prévia do cartão
  /// (o id equipado e o catálogo que o desenha) e o painel por trás, que guarda
  /// a equipe com que foi aberta. O `mounted` não é luxo: a folha pode ter
  /// fechado enquanto a recarga esperava a rede.
  Future<void> _returnedFromShop() async {
    await _loadEmblems();
    if (!mounted) return;
    widget.onChanged();
  }

  /// Abre a folha da loja da equipe. Membro sem cargo não chega aqui: o botão
  /// só existe para quem o servidor deixa comprar.
  Future<void> _pickEmblem() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => AvatarShopSheet(
        api: context.read<AppState>().api,
        teamId: widget.team.id,
        onChanged: _returnedFromShop,
      ),
    );
  }

  void _set(TeamSettings next) => setState(() => _s = next);

  void _toast(String message) {
    // Chamado no `catch` de uma escrita: se a pessoa fechou a tela enquanto a
    // requisição esperava, o messenger deste contexto já não existe.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Chamada de escrita com o erro do servidor devolvido em mensagem, e o
  /// painel recarregado no fim — nada de botão que falha em silêncio.
  Future<T?> _call<T>(Future<T> Function(ApiClient api) call) async {
    if (_busy) return null;
    setState(() => _busy = true);
    try {
      final result = await call(context.read<AppState>().api);
      // O callback é do dono da rota por baixo; ele decide se ainda faz
      // sentido recarregar. Fechar esta tela no meio da requisição não pode
      // esconder do painel uma escrita que deu certo.
      widget.onChanged();
      return result;
    } on ApiException catch (e) {
      _toast(e.message);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;
    setState(() => _saving = true);
    final draft = _s;
    try {
      await context.read<AppState>().api.updateTeam(
        id: widget.team.id,
        name: draft.name,
        joinMode: draft.joinMode.apiValue,
        listed: draft.listed,
        notifyRisk: draft.notifyRisk,
        notifyRequests: draft.notifyRequests,
      );
      if (!mounted) return;
      setState(() {
        _baseline = draft;
        _name.text = draft.name;
      });
      widget.onChanged();
      _toast('Alterações salvas');
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } catch (_) {
      if (mounted) _toast('Não foi possível salvar. Tente de novo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _cancel() {
    setState(() {
      _s = _baseline;
      _name.text = _baseline.name;
    });
  }

  Future<void> _decide(TeamJoinRequestInfo req, bool accept) async {
    final updated = await _call(
      (api) => api.decideJoinRequest(widget.team.id, req.id, accept),
    );
    // Sem retorno, a escrita não aconteceu (erro ou chamada em voo): o pedido
    // continua no servidor, então tirá-lo da lista deixaria a tela mentindo.
    if (updated == null || !mounted) return;
    setState(() => _requests = List.of(updated.pendingRequests));
  }

  Future<void> _copyLink() async {
    final link = _inviteLink;
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) _toast('Link copiado');
  }

  Future<void> _regenerate() async {
    final ok = await _confirm(
      title: 'Gerar novo link?',
      body: 'O link antigo deixa de funcionar.',
      action: 'Gerar',
    );
    if (!ok || !mounted) return;
    final updated = await _call(
      (api) => api.regenerateTeamInvite(widget.team.id),
    );
    // A falha não devolve equipe nenhuma: sair daqui sem checar apagaria o link
    // que ainda funciona e deixaria o painel sem convite.
    if (updated == null || !mounted) return;
    setState(() => _inviteLink = _linkOf(updated.inviteToken));
    _toast(_inviteLink == null ? 'Não foi possível gerar o link.' : 'Novo link gerado');
  }

  Future<void> _leave() async {
    final gone = await confirmTeamExit(context, widget.team);
    if (!gone || !mounted) return;
    widget.onChanged();
    Navigator.of(context).pop();
  }

  Future<void> _dissolve() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _DissolveDialog(teamName: _baseline.name),
    );
    if (ok != true || !mounted) return;
    // `disbandTeam` devolve vazio, então o marcador é o que separa o sucesso do
    // erro: fechar a tela numa falha mandaria a pessoa de volta ao painel com a
    // equipe ainda de pé.
    final gone = await _call((api) async {
      await api.disbandTeam(widget.team.id);
      return true;
    });
    if (gone != true || !mounted) return;
    Navigator.of(context).pop();
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) async {
    final cs = Theme.of(context).colorScheme;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Se houver alterações não salvas, pergunta antes de voltar.
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirm(
          title: 'Descartar alterações?',
          body: 'Você tem alterações que ainda não foram salvas.',
          action: 'Descartar',
          destructive: true,
        );
        if (discard && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Configurações'),
          backgroundColor: Colors.transparent,
        ),
        body: CenteredContent(
          maxWidth: kTeamSettingsMaxWidth,
          child: Form(
            key: _formKey,
            child: ListView(
              // A lista própria da tela, com chave: em janela larga o que se vê
              // é a linha de duas colunas, e os testes rolam por aqui, não por
              // `ListView`.
              key: const Key('team-settings-list'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: _sections(context),
            ),
          ),
        ),
        // Fixa embaixo: a pessoa não precisa rolar até o fim para salvar.
        bottomNavigationBar: _isAdmin
            ? _SaveBar(
                canSave: _dirty,
                saving: _saving,
                onSave: _save,
                onCancel: _cancel,
              )
            : null,
      ),
    );
  }

  /// As seções da tela, na ordem. Em janela larga elas viram duas colunas: uma
  /// coluna de 560 px no meio da tela de web sobra meio mundo de vazio dos dois
  /// lados, e vazio não é margem.
  List<Widget> _sections(BuildContext context) {
    final team = widget.team;
    final sections = <Widget>[
      _Section(title: 'Perfil da equipe', children: [
        _ProfileFields(
          team: team,
          emblem: _emblem,
          editable: _isAdmin,
          nameCtrl: _name,
          onNameChanged: (v) => _set(_s.copyWith(name: v.trim())),
          onPickEmblem: _pickEmblem,
        ),
      ]),
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        leading: const Icon(Icons.storefront_outlined),
        title: const Text('Loja da equipe'),
        subtitle: Text(
          _isAdmin
              ? 'Emblema, moldura, banner, efeito e bundles'
              : 'Veja o que a equipe tem; só dono e admin compram',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _busy
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TeamShopScreen(teamId: team.id),
                ),
              ).then((_) => _returnedFromShop()),
      ),
      ..._entrySections(context),
      if (_isAdmin) ..._inviteSection(context),
      if (_isAdmin) ..._requestsSection(context),
      if (_isAdmin) ..._noticesSection(context),
      _Section(title: 'Zona de risco', danger: true, children: [
        ListTile(
          title: const Text('Sair da equipe'),
          subtitle: Text(
            _isOwner
                ? _onlyMember
                      ? 'Como você é a única pessoa, sair apaga a equipe'
                      : 'Você vai escolher um sucessor ou dissolver'
                : 'Você deixa de ver os pontos e territórios da equipe',
          ),
          trailing: _DangerButton(
            label: 'Sair',
            onPressed: _leave,
          ),
        ),
        if (_isOwner)
          ListTile(
            title: const Text('Dissolver equipe'),
            subtitle: const Text(
              'Remove a equipe, os pontos e os membros. '
              'Não dá para desfazer',
            ),
            trailing: _DangerButton(
              label: 'Dissolver',
              onPressed: _dissolve,
            ),
          ),
      ]),
    ];
    if (!isWideWindow(context)) {
      return sections;
    }
    return [_twoColumns(sections)];
  }

  /// Divide as seções entre as duas colunas dando a próxima à mais curta: as
  /// duas terminam perto uma da outra em altura, em vez de uma descer até a
  /// zona de risco e a outra parar no meio da tela.
  Widget _twoColumns(List<Widget> sections) {
    final left = <Widget>[];
    final right = <Widget>[];
    var leftWeight = 0.0;
    var rightWeight = 0.0;
    for (final section in sections) {
      final weight = _sectionWeight(section);
      if (leftWeight <= rightWeight) {
        left.add(section);
        leftWeight += weight;
      } else {
        right.add(section);
        rightWeight += weight;
      }
    }
    return Row(
      key: const Key('team-settings-columns'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: left,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: right,
          ),
        ),
      ],
    );
  }

  /// Peso de uma seção para o balanceamento: ela vale pelos cartões que carrega,
  /// mais o título. O bloco do emblema com o campo de nome é o mais alto da tela
  /// e conta por três cartões.
  double _sectionWeight(Widget section) {
    if (section is _Section) {
      var weight = 1.0;
      for (final child in section.children) {
        weight += _childWeight(child);
      }
      return weight;
    }
    return _childWeight(section);
  }

  double _childWeight(Widget child) => child is _ProfileFields ? 3.0 : 1.0;

  bool get _onlyMember => widget.team.memberCount <= 1;

  /// Dono/admin escolhem; membro lê o que o servidor manda sobre a equipe.
  List<Widget> _entrySections(BuildContext context) {
    if (!_isAdmin) {
      final mode = JoinMode.fromApi(widget.team.joinMode);
      return [
        _Section(
          title: 'Quem pode entrar',
          children: [
            ListTile(
              title: Text(mode.title),
              subtitle: Text(mode.subtitle),
            ),
            const Divider(height: 1),
            ListTile(
              title: Text(
                widget.team.listed
                    ? 'Aparece em "Equipes disponíveis"'
                    : 'Não aparece em "Equipes disponíveis"',
              ),
              subtitle: const Text('Só dono e admin alteram isso'),
            ),
          ],
        ),
      ];
    }
    return [
      _Section(title: 'Quem pode entrar', children: [
        for (final mode in JoinMode.values)
          _OptionTile(
            mode: mode,
            selected: _s.joinMode == mode,
            onTap: () => _set(_s.copyWith(joinMode: mode)),
          ),
        const Divider(height: 1),
        SwitchListTile(
          title: const Text('Aparecer em "Equipes disponíveis"'),
          subtitle: const Text('Desligado, só quem tem o link encontra a equipe'),
          value: _s.listed,
          onChanged: (v) => _set(_s.copyWith(listed: v)),
        ),
      ]),
    ];
  }

  List<Widget> _inviteSection(BuildContext context) {
    return [
      _Section(title: 'Convites', children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Text(
                  _inviteLink ?? 'Gere um link para convidar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: _inviteLink == null ? null : _copyLink,
              child: const Text('Copiar'),
            ),
          ]),
        ),
        ListTile(
          title: const Text('Gerar novo link'),
          subtitle: const Text('O link antigo deixa de funcionar'),
          trailing: OutlinedButton(
            onPressed: _busy ? null : _regenerate,
            child: const Text('Gerar'),
          ),
        ),
      ]),
    ];
  }

  List<Widget> _requestsSection(BuildContext context) {
    return [
      _Section(title: 'Pedidos de entrada', children: [
        if (_requests.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 16, 14, 16),
            child: Text('Nenhum pedido aguardando decisão.'),
          ),
        for (final req in _requests)
          ListTile(
            leading: CircleAvatar(
              child: Text(
                req.username.isNotEmpty
                    ? req.username[0].toUpperCase()
                    : '?',
              ),
            ),
            title: Text('@${req.username}'),
            subtitle: const Text('Quer entrar na equipe'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Aceitar pedido',
                  icon: const Icon(
                    Icons.check_circle_outline,
                    color: Colors.green,
                  ),
                  onPressed: _busy ? null : () => _decide(req, true),
                ),
                IconButton(
                  tooltip: 'Recusar pedido',
                  icon: Icon(
                    Icons.cancel_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: _busy ? null : () => _decide(req, false),
                ),
              ],
            ),
          ),
      ]),
    ];
  }

  List<Widget> _noticesSection(BuildContext context) {
    return [
      _Section(title: 'Avisos da equipe', children: [
        // As chaves ficam na equipe, não na pessoa: um switch aqui muda o
        // aviso de todo mundo, por isso o texto avisa antes da pessoa mexer.
        SwitchListTile(
          title: const Text('Território em risco'),
          subtitle: const Text(
            'Avisar todos os membros quando alguém tomar uma zona nossa',
          ),
          value: _s.notifyRisk,
          onChanged: (v) => _set(_s.copyWith(notifyRisk: v)),
        ),
        SwitchListTile(
          title: const Text('Novos pedidos de entrada'),
          subtitle: const Text('Avisar dono e admins a cada pedido'),
          value: _s.notifyRequests,
          onChanged: (v) => _set(_s.copyWith(notifyRequests: v)),
        ),
      ]),
    ];
  }
}

/// Nome e emblema. Dono/admin editam; membro vê os valores salvos.
class _ProfileFields extends StatelessWidget {
  const _ProfileFields({
    required this.team,
    required this.emblem,
    required this.editable,
    required this.nameCtrl,
    required this.onNameChanged,
    required this.onPickEmblem,
  });

  final TeamDetail team;
  final ShopItem? emblem;
  final bool editable;
  final TextEditingController nameCtrl;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onPickEmblem;

  @override
  Widget build(BuildContext context) {
    // O rosto é o do item equipado (a seed é o id do item); a foto da equipe
    // aparece quando não há emblema da loja — a mesma regra do painel.
    final image = profileAvatarImage(team.photoUrl, emblem);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            team.isOwner
                ? 'Você é o dono desta equipe.'
                : team.isAdmin
                ? 'Você é admin desta equipe.'
                : 'Você é membro: estes dados são da equipe e você pode sair.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.15),
                foregroundImage: image,
                onForegroundImageError: image == null ? null : (_, _) {},
                child: Text(
                  team.name.isNotEmpty ? team.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  editable
                      ? 'O emblema é item da Loja da equipe. Moldura, banner e '
                            'efeito ficam lá junto.'
                      : 'O emblema é item da Loja da equipe. Só o dono ou admins '
                            'mudam.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (editable) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('team-pick-emblem'),
                onPressed: onPickEmblem,
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('Escolher emblema na loja'),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: nameCtrl,
              maxLength: 40,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: const InputDecoration(
                labelText: 'Nome da equipe',
                border: OutlineInputBorder(),
              ),
              // Os mesmos limites do servidor (2..40): validar menos que isso
              // deixa o campo "ok" no app e voltar 400 na salvada.
              validator: (v) {
                final name = (v ?? '').trim();
                if (name.length < 2) return 'O nome precisa de pelo menos 2 letras';
                if (name.length > 40) return 'O nome pode ter no máximo 40 letras';
                return null;
              },
              onChanged: onNameChanged,
            ),
          ] else ...[
            Text(
              team.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${team.memberCount} ${team.memberCount == 1 ? 'membro' : 'membros'} · '
              'criada por @${team.creatorUsername}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ Peças

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.danger = false,
  });

  final String title;
  final List<Widget> children;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(
              letterSpacing: 0.8,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: danger ? BorderSide(color: cs.error.withAlpha(120)) : BorderSide.none,
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// Opção de escolha única. Usei ListTile em vez de RadioListTile para não
/// depender de qual versão do Flutter você usa (a API do Radio mudou).
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final JoinMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      child: ListTile(
        selected: selected,
        onTap: onTap,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        ),
        title: Text(mode.title),
        subtitle: Text(mode.subtitle),
      ),
    );
  }
}

class _DangerButton extends StatelessWidget {
  const _DangerButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: error,
        side: BorderSide(color: error),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.canSave,
    required this.saving,
    required this.onSave,
    required this.onCancel,
  });

  final bool canSave, saving;
  final VoidCallback onSave, onCancel;

  @override
  Widget build(BuildContext context) {
    final enabled = canSave && !saving;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        // Align com heightFactor (e não Center): o Scaffold mede a
        // bottomNavigationBar com folga total, e o Center preencheria a
        // tela inteira, esmagando o body para altura zero.
        child: Align(
          alignment: Alignment.center,
          heightFactor: 1.0,
          child: ConstrainedBox(
            // A barra acompanha a largura padrão do conteúdo, não o miolo de
            // duas colunas: dois botões de 500 px cada não são um salvar melhor.
            constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: enabled ? onCancel : null,
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: FilledButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: enabled ? onSave : null,
                    child: saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Salvar alterações'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dissolução pede o nome da equipe digitado: é a ação sem volta do time.
class _DissolveDialog extends StatefulWidget {
  const _DissolveDialog({required this.teamName});

  final String teamName;

  @override
  State<_DissolveDialog> createState() => _DissolveDialogState();
}

class _DissolveDialogState extends State<_DissolveDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final matches = _controller.text.trim() == widget.teamName;
    return AlertDialog(
      title: const Text('Dissolver equipe?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.teamName} deixará de existir para todos os membros. '
            'Territórios voltam a ficar livres e a loja da equipe é apagada. '
            'Não há como desfazer.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Digite ${widget.teamName} para confirmar',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: cs.error,
            foregroundColor: cs.onError,
          ),
          onPressed: matches ? () => Navigator.pop(context, true) : null,
          child: const Text('Dissolver'),
        ),
      ],
    );
  }
}

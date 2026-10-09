import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../services/api_client.dart';
import '../services/data_export_share.dart';
import '../services/profile_image_provider.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/avatar_shop_sheet.dart';
import '../widgets/cosmetics.dart';
import '../widgets/owned_cosmetics.dart';
import 'terms_screen.dart';

/// Dias da semana (código da API + rótulo curto em pt).
const _weekdays = [
  ('seg', 'Seg'),
  ('ter', 'Ter'),
  ('qua', 'Qua'),
  ('qui', 'Qui'),
  ('sex', 'Sex'),
  ('sab', 'Sáb'),
  ('dom', 'Dom'),
];

/// Níveis de atividade (valor da API + rótulo em pt).
const _activityLevels = [
  ('iniciante', 'Iniciante'),
  ('baixo_impacto', 'Baixo impacto'),
  ('moderado', 'Moderado'),
  ('cardio', 'Cardio'),
];

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile});
  final UserProfile profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _username;
  late final TextEditingController _photo;
  late final TextEditingController _pronouns;
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  late bool _public;
  late bool _shareActivities;
  // Preferências de treino.
  late String _units;
  int? _frequency;
  late Set<String> _days;
  String? _activity;
  String? _accent;
  bool _editingPhoto = false;
  bool _pickingPhoto = false;
  // URL cuja imagem falhou ao carregar no avatar (ex.: link bloqueado por
  // CORS no web). Comparada com o texto atual: some sozinha ao trocar a foto.
  String? _photoFailedUrl;
  bool _changePassword = false;
  bool _showPassword = false;
  bool _saving = false;
  bool _saved = false;
  bool _exporting = false;
  bool _leaving = false;
  String? _error;
  // Navegação do painel de ajustes (master-detail): qual secção aparece
  // no painel de conteúdo. O estado do formulário é preservado ao trocar.
  String _section = 'perfil';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.fullName);
    _username = TextEditingController(text: widget.profile.username);
    _photo = TextEditingController(text: widget.profile.photoUrl ?? '');
    _pronouns = TextEditingController(text: widget.profile.pronouns ?? '');
    _public = widget.profile.isPublic;
    _shareActivities = widget.profile.shareActivities;
    _units = widget.profile.distanceUnits;
    _frequency = widget.profile.weeklyFrequency;
    _days = widget.profile.trainingDays.toSet();
    _activity = widget.profile.activityLevel;
    _accent = widget.profile.accentColor;
    for (final controller in [
      _name,
      _username,
      _photo,
      _pronouns,
      _password,
      _confirmation,
    ]) {
      controller.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  bool get _dirty =>
      _name.text.trim() != widget.profile.fullName ||
      _username.text.trim() != widget.profile.username ||
      _photo.text.trim() != (widget.profile.photoUrl ?? '') ||
      _pronouns.text.trim() != (widget.profile.pronouns ?? '') ||
      _public != widget.profile.isPublic ||
      _shareActivities != widget.profile.shareActivities ||
      _units != widget.profile.distanceUnits ||
      _frequency != widget.profile.weeklyFrequency ||
      _days.length != widget.profile.trainingDays.length ||
      !_days.containsAll(widget.profile.trainingDays) ||
      _activity != widget.profile.activityLevel ||
      _accent != widget.profile.accentColor ||
      (_changePassword &&
          (_password.text.isNotEmpty || _confirmation.text.isNotEmpty));

  @override
  void dispose() {
    for (final controller in [
      _name,
      _username,
      _photo,
      _pronouns,
      _password,
      _confirmation,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _leave() async {
    if (_saving || _leaving) return;
    _leaving = true;
    final discard =
        !_dirty ||
        await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Descartar alterações?'),
                content: const Text(
                  'As alterações que você fez ainda não foram salvas.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Continuar editando'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Descartar'),
                  ),
                ],
              ),
            ) ==
            true;
    if (!mounted) return;
    _leaving = false;
    if (discard) {
      setState(() => _saved = true);
      // Atualiza o PopScope antes de executar a navegação autorizada.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  void _flagPhotoLoadFailure(String failedUrl) {
    if (_photoFailedUrl == failedUrl || !mounted) return;
    // O erro de carregamento chega durante o layout: agenda o setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _photo.text.trim() == failedUrl) {
        setState(() => _photoFailedUrl = failedUrl);
      }
    });
  }

  String? _photoError(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    if (text.startsWith('data:')) {
      return isProfilePhotoDataUri(text)
          ? null
          : 'Escolha uma imagem JPG, PNG ou WebP.';
    }
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      return 'Informe um link de imagem começando com https://.';
    }
    return null;
  }

  Future<void> _showPresetAvatars() async {
    if (_saving) return;
    final app = context.read<AppState>();
    final username = _username.text.trim().isEmpty
        ? widget.profile.username
        : _username.text.trim();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => AvatarShopSheet(
        username: username,
        api: app.api,
        onChanged: () => app.refreshProfile(),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    if (_saving || _pickingPhoto) return;
    setState(() {
      _pickingPhoto = true;
      _error = null;
    });
    try {
      // A galeria abre dentro do app (no celular) ou o seletor de arquivos
      // (no navegador/desktop). O redimensionamento é refeito abaixo em Dart
      // porque o plugin ignora essas opções no web.
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;
      final avatar = fitAvatarPhoto(await image.readAsBytes());
      if (avatar == null) {
        setState(() => _error = 'Escolha uma imagem JPG, PNG ou WebP.');
        return;
      }
      if (avatar.bytes.length > maxAvatarBytes) {
        setState(
          () =>
              _error = 'A imagem ficou grande demais. Escolha uma foto menor.',
        );
        return;
      }
      _photo.text =
          'data:${avatar.mimeType};base64,${base64Encode(avatar.bytes)}';
      setState(() => _editingPhoto = false);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Não foi possível abrir a foto. Tente escolher outra imagem.',
        );
      }
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  String? _passwordError(String? value) {
    if (!_changePassword) return null;
    final text = value ?? '';
    if (text.runes.length < 8 ||
        !RegExp(r'\p{L}', unicode: true).hasMatch(text) ||
        !RegExp(r'\p{N}', unicode: true).hasMatch(text)) {
      return 'Use pelo menos 8 caracteres, incluindo letras e números.';
    }
    if (utf8.encode(text).length > 72) {
      return 'A senha ultrapassa o limite de 72 bytes.';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving || _saved) return;
    if (_photoError(_photo.text) != null) {
      setState(() => _editingPhoto = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _form.currentState?.validate();
      });
      return;
    }
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final state = context.read<AppState>();
    if (state.profile?.id != widget.profile.id) {
      setState(
        () => _error =
            'Sua sessão mudou. Volte ao perfil para conferir seus dados.',
      );
      return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final changePassword = _changePassword;
    var logoutFailed = false;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await state.api.updateProfile(
        fullName: _name.text.trim(),
        username: _username.text.trim(),
        photoUrl: _photo.text.trim(),
        pronouns: _pronouns.text.trim(),
        accentColor: _accent ?? '',
        isPublic: _public,
        shareActivities: _shareActivities,
        password: changePassword ? _password.text : null,
        distanceUnits: _units,
        weeklyFrequency: _frequency,
        trainingDays: [
          for (final w in _weekdays)
            if (_days.contains(w.$1)) w.$1,
        ],
        activityLevel: _activity,
      );
      if (!mounted) return;
      if (state.profile?.id != widget.profile.id) {
        setState(
          () => _error =
              'Sua sessão mudou durante a atualização. Volte ao perfil para conferir os dados.',
        );
        return;
      }
      if (changePassword) {
        try {
          await state.logout();
        } catch (_) {
          logoutFailed = true;
        }
        if (!mounted) return;
      } else {
        state.applyUpdatedProfile(updated);
      }
      setState(() {
        _saved = true;
        _saving = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (changePassword) {
          navigator.popUntil((route) => route.isFirst);
        } else {
          navigator.pop();
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              logoutFailed
                  ? 'Senha alterada. Não foi possível limpar o acesso salvo neste navegador. Limpe os dados do site antes de entrar novamente.'
                  : changePassword
                  ? 'Senha alterada. Entre novamente com sua nova senha.'
                  : 'Perfil atualizado.',
            ),
          ),
        );
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Não foi possível concluir a atualização. Verifique sua conexão e tente novamente.',
        );
      }
    } finally {
      if (mounted && !_saved) setState(() => _saving = false);
    }
  }

  static const _sections = [
    ('perfil', 'Perfil', Icons.person_outline),
    ('conta', 'Conta', Icons.badge_outlined),
    ('aparencia', 'Aparência', Icons.palette_outlined),
    ('privacidade', 'Privacidade', Icons.lock_outline),
    ('treino', 'Treino', Icons.directions_run),
    ('seguranca', 'Segurança', Icons.shield_outlined),
  ];

  List<(String, String, IconData)> get _visibleSections {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _sections;
    return _sections.where((s) => s.$2.toLowerCase().contains(q)).toList();
  }

  (String, String) get _sectionHeader => switch (_section) {
    'conta' => ('Conta', 'Nome, apelido e e-mail da sua identidade.'),
    'aparencia' => (
      'Aparência',
      'Tema claro, escuro ou do sistema. Aplica na hora.',
    ),
    'privacidade' => ('Privacidade', 'Quem pode ver seu perfil e seus dados.'),
    'treino' => ('Treino', 'Unidades, metas semanais e nível de atividade.'),
    'seguranca' => ('Segurança', 'Senha e acesso à conta.'),
    _ => ('Meu perfil', 'Sua identidade dentro e fora dos territórios.'),
  };

  void _selectSection(String id) {
    if (_section == id) return;
    setState(() => _section = id);
  }

  Widget _sidebar({required bool vertical}) {
    final items = _visibleSections;
    if (vertical) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Pesquisar configuração',
                    prefixIcon: Icon(Icons.search, size: 18),
                    contentPadding: EdgeInsets.symmetric(vertical: 0),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              for (final (id, label, icon) in items)
                _sidebarTile(id, label, icon),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Nenhuma secção corresponde à pesquisa.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: 'Pesquisar configuração',
            prefixIcon: Icon(Icons.search, size: 18),
            contentPadding: EdgeInsets.symmetric(vertical: 0),
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (id, label, icon) in items)
              ChoiceChip(
                key: Key('settings-tab-$id'),
                label: Text(label),
                avatar: Icon(icon, size: 18),
                selected: _section == id,
                onSelected: (_) => _selectSection(id),
              ),
          ],
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Nenhuma secção corresponde à pesquisa.'),
          ),
      ],
    );
  }

  Widget _sidebarTile(String id, String label, IconData icon) {
    final selected = _section == id;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        key: Key('settings-tab-$id'),
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        selected: selected,
        selectedTileColor: colors.primary.withValues(alpha: 0.12),
        leading: Icon(
          icon,
          size: 18,
          color: selected ? colors.primary : colors.onSurfaceVariant,
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? colors.onSurface : colors.onSurfaceVariant,
          ),
        ),
        onTap: () => _selectSection(id),
      ),
    );
  }

  Widget _contentCard() {
    final (title, subtitle) = _sectionHeader;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            const Divider(height: 1),
            ..._activeSectionFields(),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : _leave,
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(_saving ? 'Salvando…' : 'Salvar alterações'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String title, Widget child) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final label = Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        );
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [label, const SizedBox(height: 12), child],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 165,
              child: Padding(
                padding: const EdgeInsets.only(top: 14, right: 24),
                child: label,
              ),
            ),
            Expanded(child: child),
          ],
        );
      },
    ),
  );

  List<Widget> _activeSectionFields() {
    switch (_section) {
      case 'conta':
        return _accountFields();
      case 'aparencia':
        return _appearanceFields();
      case 'privacidade':
        return _privacyFields();
      case 'treino':
        return _trainingFields();
      case 'seguranca':
        return _securityFields();
      default:
        return _profileFields();
    }
  }

  List<Widget> _profileFields() {
    final photoUrl = _photo.text.trim();
    final photoImage = profileImageProvider(photoUrl);
    final canPreview = photoImage != null;
    return [
      _row(
        'Foto atual',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundColor: RunoverColors.route.withValues(alpha: .12),
                  foregroundImage: canPreview ? photoImage : null,
                  onForegroundImageError: canPreview
                      ? (_, _) => _flagPhotoLoadFailure(photoUrl)
                      : null,
                  child: const Icon(
                    Icons.person_outline,
                    size: 42,
                    color: RunoverColors.route,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: _saving || _pickingPhoto ? null : _pickPhoto,
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          size: 18,
                        ),
                        label: Text(
                          _pickingPhoto ? 'Abrindo…' : 'Escolher arquivo',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _saving || _pickingPhoto
                            ? null
                            : _showPresetAvatars,
                        icon: const Icon(Icons.face_outlined, size: 18),
                        label: const Text('Avatares'),
                      ),
                      TextButton.icon(
                        onPressed: _saving || _pickingPhoto
                            ? null
                            : () => setState(
                                () => _editingPhoto = !_editingPhoto,
                              ),
                        icon: const Icon(Icons.link, size: 18),
                        label: const Text('Alterar foto'),
                      ),
                      if (photoUrl.isNotEmpty)
                        TextButton(
                          onPressed: _saving ? null : _photo.clear,
                          child: const Text('Remover'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (_photoFailedUrl == photoUrl && photoUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Não foi possível carregar esta imagem. Confira o link ou escolha um arquivo do dispositivo.',
                    ),
                  ),
                ],
              ),
            ],
            if (_editingPhoto) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _photo,
                enabled: !_saving,
                validator: _photoError,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Link da foto',
                  hintText: 'https://exemplo.com/foto.jpg',
                  helperText:
                      'Ou escolha uma imagem dos arquivos do dispositivo.',
                  helperMaxLines: 2,
                ),
              ),
            ],
            const Divider(height: 1),
            _row(
              'Cor de destaque',
              AccentPicker(
                value: _accent,
                onChanged: (v) => setState(() => _accent = v),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _accountFields() => [
    _row(
      'Nome',
      TextFormField(
        controller: _name,
        enabled: !_saving,
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.name],
        decoration: const InputDecoration(
          labelText: 'Nome',
          hintText: 'Como você se chama?',
        ),
        validator: (value) {
          final length = (value ?? '').trim().runes.length;
          return length < 2 || length > 120
              ? 'Use entre 2 e 120 caracteres.'
              : null;
        },
      ),
    ),
    const Divider(height: 1),
    _row(
      'Pronomes',
      TextFormField(
        controller: _pronouns,
        enabled: !_saving,
        maxLength: 80,
        decoration: const InputDecoration(
          hintText: 'Ex.: ele/dele',
          helperText: 'Opcional. Será exibido no seu perfil.',
        ),
      ),
    ),
    const Divider(height: 1),
    _row(
      'Nome de usuário',
      TextFormField(
        controller: _username,
        enabled: !_saving,
        autocorrect: false,
        autofillHints: const [AutofillHints.username],
        decoration: const InputDecoration(
          labelText: 'Nome de usuário',
          prefixText: '@',
          helperText: 'Seu identificador no Runover.',
        ),
        validator: (value) {
          final length = (value ?? '').trim().runes.length;
          return length < 3 || length > 24
              ? 'Use entre 3 e 24 caracteres.'
              : null;
        },
      ),
    ),
    const Divider(height: 1),
    _row(
      'E-mail',
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          widget.profile.email,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ),
    const Divider(height: 1),
    _row(
      'Equipe',
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          widget.profile.teamName ?? 'Você ainda não participa de uma equipe.',
        ),
      ),
    ),
  ];

  List<Widget> _appearanceFields() {
    final mode = context.watch<AppState>().themeMode;
    Widget option(ThemeMode value, String label, IconData icon) {
      return RadioListTile<ThemeMode>(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: value,
        title: Text(label),
        secondary: Icon(icon, size: 20),
      );
    }

    return [
      _row(
        'Cosméticos comprados',
        OwnedCosmeticsPanel(
          api: context.read<AppState>().api,
          onChanged: () => context.read<AppState>().refreshProfile(),
        ),
      ),
      _row(
        'Tema',
        RadioGroup<ThemeMode>(
          groupValue: mode,
          onChanged: (next) {
            if (next != null) context.read<AppState>().setThemeMode(next);
          },
          child: Column(
            children: [
              option(
                ThemeMode.system,
                'Sistema',
                Icons.brightness_auto_outlined,
              ),
              option(ThemeMode.light, 'Claro', Icons.light_mode_outlined),
              option(ThemeMode.dark, 'Escuro', Icons.dark_mode_outlined),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _privacyFields() => [
    _row(
      'Privacidade',
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: _public,
        onChanged: _saving ? null : (value) => setState(() => _public = value),
        title: const Text('Perfil público'),
        subtitle: const Text(
          'Permite que outros jogadores consultem seu perfil.',
        ),
      ),
    ),
    _row(
      'Atividades',
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: _shareActivities,
        onChanged: _saving
            ? null
            : (value) => setState(() => _shareActivities = value),
        title: const Text('Compartilhar minhas atividades'),
        subtitle: const Text(
          'Permite que corridas e conquistas apareçam para outros jogadores. '
          'Desative para manter suas atividades privadas.',
        ),
      ),
    ),
    _row(
      'Meus dados',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Baixe tudo que o app guarda sobre você (conta, corridas, histórico e mais), em JSON.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _exporting || _saving ? null : _exportData,
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined, size: 18),
            label: Text(_exporting ? 'Preparando…' : 'Baixar meus dados'),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _trainingFields() => [
    _row(
      'Unidades',
      RadioGroup<String>(
        groupValue: _units,
        onChanged: (value) {
          if (!_saving) {
            setState(() => _units = value ?? 'km');
          }
        },
        child: Column(
          children: [
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              enabled: !_saving,
              title: const Text('Quilômetros (km)'),
              value: 'km',
            ),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              enabled: !_saving,
              title: const Text('Milhas (mi)'),
              value: 'mi',
            ),
          ],
        ),
      ),
    ),
    const Divider(height: 1),
    _row(
      'Metas',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<int?>(
            initialValue: _frequency,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Frequência semanal',
              helperText: 'Quantos dias por semana você planeja correr.',
            ),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Sem meta definida'),
              ),
              for (var d = 1; d <= 7; d++)
                DropdownMenuItem(
                  value: d,
                  child: Text(
                    d == 1 ? '1 dia por semana' : '$d dias por semana',
                  ),
                ),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => _frequency = value),
          ),
          const SizedBox(height: 16),
          const Text('Dias livres para treinar'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (code, label) in _weekdays)
                _DayToggle(
                  label: label,
                  selected: _days.contains(code),
                  onTap: _saving
                      ? null
                      : () => setState(() {
                          if (!_days.remove(code)) {
                            _days.add(code);
                          }
                        }),
                ),
            ],
          ),
        ],
      ),
    ),
    const Divider(height: 1),
    _row(
      'Saúde',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String?>(
            initialValue: _activity,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Nível de atividade atual',
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Não informado')),
              for (final (value, label) in _activityLevels)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => _activity = value),
          ),
          const SizedBox(height: 12),
          Text(
            'Ajustes de treino não substituem aconselhamento médico. Em caso de dúvida, procure um profissional de saúde.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const TermsScreen())),
              child: const Text('Política de Privacidade'),
            ),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _securityFields() => [
    _row(
      'Segurança',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _changePassword,
            onChanged: _saving
                ? null
                : (value) => setState(() => _changePassword = value),
            title: const Text('Alterar senha'),
            subtitle: const Text(
              'Você precisará entrar novamente após a alteração.',
            ),
          ),
          if (_changePassword) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              enabled: !_saving,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              validator: _passwordError,
              decoration: InputDecoration(
                labelText: 'Nova senha',
                errorMaxLines: 3,
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Ocultar senha' : 'Mostrar senha',
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmation,
              enabled: !_saving,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Confirmar nova senha',
              ),
              validator: (value) =>
                  value != _password.text ? 'As senhas não coincidem.' : null,
            ),
          ],
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 16),
          const Text(
            'Desative sua conta',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Desative temporariamente sua conta. Seu perfil some para os '
            'outros e o login é bloqueado, mas nada é apagado — reative '
            'quando quiser entrando novamente.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _saving ? null : _confirmDeactivate,
            icon: const Icon(Icons.pause_circle_outline, size: 18),
            label: const Text('Desativar conta'),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Text(
            'Zona de perigo',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Encerre sua conta permanentemente. Esta ação apaga tudo e '
            'não pode ser desfeita.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _saving ? null : _confirmDelete,
            icon: const Icon(Icons.delete_forever_outlined, size: 18),
            label: const Text('Excluir conta'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    ),
  ];

  /// Portabilidade LGPD: baixa o JSON e entrega via compartilhamento.
  Future<void> _exportData() async {
    if (_exporting || _saving) return;
    setState(() => _exporting = true);
    try {
      final data = await context.read<AppState>().api.exportData();
      final ok = await shareExportedJson(
        'runover-meus-dados.json',
        const JsonEncoder.withIndent('  ').convert(data),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Dados prontos para salvar ou enviar.'
                : 'Não foi possível entregar os dados. Tente novamente.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Desativação temporária: confirma, chama a API e volta ao login.
  /// Nada é apagado — a conta volta com POST /auth/reactivate.
  Future<void> _confirmDeactivate() async {
    var deactivating = false;
    String? dialogError;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Desativar conta?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sua conta fica pausada: seu perfil some para os outros '
                'e o login é bloqueado, mas nada é apagado.',
              ),
              const SizedBox(height: 8),
              const Text('Reative quando quiser entrando novamente.'),
              if (dialogError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    dialogError!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: deactivating
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: deactivating
                  ? null
                  : () async {
                      final navigator = Navigator.of(context);
                      setDialogState(() {
                        deactivating = true;
                        dialogError = null;
                      });
                      try {
                        final app = context.read<AppState>();
                        await app.api.deactivateAccount();
                        await app.logout();
                      } on ApiException catch (e) {
                        setDialogState(() {
                          deactivating = false;
                          dialogError = e.message;
                        });
                        return;
                      } catch (_) {
                        setDialogState(() {
                          deactivating = false;
                          dialogError =
                              'Não foi possível desativar. Tente novamente.';
                        });
                        return;
                      }
                      if (!mounted) return;
                      navigator.pop();
                      navigator.popUntil((route) => route.isFirst);
                    },
              child: deactivating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Desativar conta'),
            ),
          ],
        ),
      ),
    );
  }

  /// Confirmação em duas etapas, estilo Meta: explica as consequências,
  /// exige ciência explícita e só então exclui.
  Future<void> _confirmDelete() async {
    var acknowledged = false;
    var deleting = false;
    String? dialogError;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Excluir conta?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Esta ação é permanente e apaga:'),
                const SizedBox(height: 8),
                const Text(
                  '• Perfil, foto, corridas e trajetos\n'
                  '• Histórico, pontos e notificações\n'
                  '• Territórios voltam a ficar livres',
                ),
                const SizedBox(height: 8),
                const Text('Se você participa de uma equipe, saia dela antes.'),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: acknowledged,
                  onChanged: deleting
                      ? null
                      : (value) =>
                            setDialogState(() => acknowledged = value ?? false),
                  title: const Text(
                    'Entendo que esta ação não pode ser desfeita.',
                  ),
                ),
                if (dialogError != null)
                  Text(
                    dialogError!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: deleting
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: !acknowledged || deleting
                  ? null
                  : () async {
                      final navigator = Navigator.of(context);
                      setDialogState(() {
                        deleting = true;
                        dialogError = null;
                      });
                      try {
                        final app = context.read<AppState>();
                        await app.api.deleteAccount();
                        await app.logout();
                      } on ApiException catch (e) {
                        setDialogState(() {
                          deleting = false;
                          dialogError = e.message;
                        });
                        return;
                      } catch (_) {
                        setDialogState(() {
                          deleting = false;
                          dialogError =
                              'Não foi possível excluir. Tente novamente.';
                        });
                        return;
                      }
                      if (!mounted) return;
                      navigator.pop();
                      navigator.popUntil((route) => route.isFirst);
                    },
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              child: deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Excluir conta'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _saved || (!_dirty && !_saving),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Editar perfil'),
          leading: IconButton(
            tooltip: 'Voltar',
            onPressed: _saving ? null : _leave,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Form(
                  key: _form,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 760) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sidebar(vertical: false),
                            const SizedBox(height: 16),
                            _contentCard(),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 260, child: _sidebar(vertical: true)),
                          const SizedBox(width: 16),
                          Expanded(child: _contentCard()),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botão redondo de dia da semana, com destaque laranja quando ativo.
class _DayToggle extends StatelessWidget {
  const _DayToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? RunoverColors.route : colors.surfaceContainerHighest,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: selected ? Colors.white : colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

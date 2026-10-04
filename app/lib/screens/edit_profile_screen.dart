import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../theme.dart';

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
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  late bool _public;
  bool _editingPhoto = false;
  bool _changePassword = false;
  bool _showPassword = false;
  bool _saving = false;
  bool _saved = false;
  bool _leaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.fullName);
    _username = TextEditingController(text: widget.profile.username);
    _photo = TextEditingController(text: widget.profile.photoUrl ?? '');
    _public = widget.profile.isPublic;
    for (final controller in [
      _name,
      _username,
      _photo,
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
      _public != widget.profile.isPublic ||
      (_changePassword &&
          (_password.text.isNotEmpty || _confirmation.text.isNotEmpty));

  @override
  void dispose() {
    for (final controller in [
      _name,
      _username,
      _photo,
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

  String? _photoError(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      return 'Informe um link de imagem começando com https://.';
    }
    return null;
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
        isPublic: _public,
        password: changePassword ? _password.text : null,
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

  Widget _row(String title, Widget child) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final label = Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
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

  @override
  Widget build(BuildContext context) {
    final photoUrl = _photo.text.trim();
    final canPreview = photoUrl.isNotEmpty && _photoError(photoUrl) == null;
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
                constraints: const BoxConstraints(maxWidth: 900),
                child: Form(
                  key: _form,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 12),
                          const Text(
                            'Meu perfil',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Sua identidade dentro e fora dos territórios.',
                            style: TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 20),
                          const Divider(height: 1),
                          _row(
                            'Foto atual',
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 42,
                                      backgroundColor: RunoverColors.route
                                          .withValues(alpha: .12),
                                      foregroundImage: canPreview
                                          ? NetworkImage(photoUrl)
                                          : null,
                                      onForegroundImageError: canPreview
                                          ? (_, _) {}
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
                                            onPressed: _saving
                                                ? null
                                                : () => setState(
                                                    () => _editingPhoto =
                                                        !_editingPhoto,
                                                  ),
                                            icon: const Icon(
                                              Icons.link,
                                              size: 18,
                                            ),
                                            label: const Text('Alterar foto'),
                                          ),
                                          if (photoUrl.isNotEmpty)
                                            TextButton(
                                              onPressed: _saving
                                                  ? null
                                                  : _photo.clear,
                                              child: const Text('Remover'),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
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
                                          'Use o link público de uma imagem.',
                                      helperMaxLines: 2,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Divider(height: 1),
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
                                final length = (value ?? '')
                                    .trim()
                                    .runes
                                    .length;
                                return length < 2 || length > 120
                                    ? 'Use entre 2 e 120 caracteres.'
                                    : null;
                              },
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
                                final length = (value ?? '')
                                    .trim()
                                    .runes
                                    .length;
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
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          _row(
                            'Equipe',
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Text(
                                widget.profile.teamName ??
                                    'Você ainda não participa de uma equipe.',
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          _row(
                            'Privacidade',
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              value: _public,
                              onChanged: _saving
                                  ? null
                                  : (value) => setState(() => _public = value),
                              title: const Text('Perfil público'),
                              subtitle: const Text(
                                'Permite que outros jogadores consultem seu perfil.',
                              ),
                            ),
                          ),
                          const Divider(height: 1),
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
                                      : (value) => setState(
                                          () => _changePassword = value,
                                        ),
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
                                        tooltip: _showPassword
                                            ? 'Ocultar senha'
                                            : 'Mostrar senha',
                                        onPressed: () => setState(
                                          () => _showPassword = !_showPassword,
                                        ),
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
                                        value != _password.text
                                        ? 'As senhas não coincidem.'
                                        : null,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (_error != null) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onErrorContainer,
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
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                    ),
                                    child: Text(
                                      _saving
                                          ? 'Salvando…'
                                          : 'Salvar alterações',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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

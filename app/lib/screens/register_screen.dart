import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../state/app_state.dart';
import 'email_confirmation_screen.dart';
import 'terms_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _photoCtrl = TextEditingController();
  bool _acceptedTerms = false;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      setState(
        () => _error =
            'É necessário aceitar os termos de uso e a política de privacidade.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await context.read<AppState>().register(
        _nameCtrl.text.trim(),
        _usernameCtrl.text.trim(),
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
        photoUrl: _photoCtrl.text.trim(),
      );
      if (!mounted) return;
      if (!result.requiresVerification) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        return;
      }
      // A conta foi criada, mas a porta ainda está fechada: sem o código do
      // e-mail não há sessão e, portanto, não há aplicativo.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EmailConfirmationScreen(
            email: result.email,
            expiresInMinutes: result.expiresInMinutes,
            resendAfterSeconds: result.resendAfterSeconds,
          ),
        ),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível conectar ao servidor.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nome completo',
                      ),
                      validator: (v) => (v == null || v.trim().length < 2)
                          ? 'Informe seu nome.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _usernameCtrl,
                      decoration: const InputDecoration(labelText: 'Nickname'),
                      validator: (v) => (v == null || v.trim().length < 3)
                          ? 'Mínimo de 3 caracteres.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'E-mail'),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'E-mail inválido.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Senha'),
                      validator: (v) {
                        if (v == null || v.length < 8) {
                          return 'Mínimo de 8 caracteres.';
                        }
                        if (!v.contains(RegExp(r'[A-Za-z]')) ||
                            !v.contains(RegExp(r'[0-9]'))) {
                          return 'Use letras e números.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirme a senha',
                      ),
                      validator: (v) => v != _passwordCtrl.text
                          ? 'As senhas não coincidem.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _photoCtrl,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Foto de perfil — URL (opcional)',
                        hintText: 'https://...',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Enviamos um código para o seu e-mail. Só depois de '
                      'digitá-lo é que a conta entra no aplicativo.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _acceptedTerms,
                      onChanged: (v) =>
                          setState(() => _acceptedTerms = v ?? false),
                      title: const Text(
                        'Li e concordo com os Termos de Uso e a Política de Privacidade.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const TermsScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.description_outlined, size: 18),
                        label: const Text(
                          'Ler os Termos de Uso e a Política de Privacidade',
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Confirmar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

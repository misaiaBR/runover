import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_client.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';
import 'terms_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _rememberedEmailKey = 'runover.remembered_login_email';

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _rememberEmail = false;
  bool _showPassword = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRememberedEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_rememberedEmailKey);
      if (!mounted || email == null || email.isEmpty) return;
      setState(() {
        _emailCtrl.text = email;
        _rememberEmail = true;
      });
    } catch (_) {
      // Keep login available on platforms where local preferences are unavailable.
    }
  }

  Future<void> _persistRememberedEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = _emailCtrl.text.trim();
      if (_rememberEmail && email.isNotEmpty) {
        await prefs.setString(_rememberedEmailKey, email);
      } else {
        await prefs.remove(_rememberedEmailKey);
      }
    } catch (_) {
      // Remembering the email is optional and must not block authentication.
    }
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _persistRememberedEmail();
    if (!mounted) return;
    try {
      await context.read<AppState>().login(_emailCtrl.text.trim(), _passwordCtrl.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível conectar ao servidor.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openTerms() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TermsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RunoverColors.ink,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF102A30),
                    RunoverColors.ink,
                    Color(0xFF2B211D),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -145,
            right: -120,
            child: _ambientGlow(RunoverColors.territory.withValues(alpha: 0.32)),
          ),
          Positioned(
            bottom: -170,
            left: -125,
            child: _ambientGlow(RunoverColors.route.withValues(alpha: 0.24)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xF2161B22),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: RunoverColors.paper.withValues(alpha: 0.11),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.32),
                          blurRadius: 36,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _brand,
                        const SizedBox(height: 28),
                        Text(
                          'Fazer login',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: RunoverColors.paper,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          'Entre para acompanhar suas corridas e territórios.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: RunoverColors.paper.withValues(alpha: 0.72),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 26),
                        _emailField,
                        const SizedBox(height: 14),
                        _passwordField,
                        const SizedBox(height: 4),
                        _accountOptions,
                        if (_error != null) ...[
                          const SizedBox(height: 6),
                          _errorMessage,
                        ],
                        const SizedBox(height: 16),
                        _loginButton,
                        const SizedBox(height: 16),
                        _createAccount,
                        const SizedBox(height: 10),
                        _termsNotice,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ambientGlow(Color color) {
    return IgnorePointer(
      child: Container(
        width: 360,
        height: 360,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }

  Widget get _brand => Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: RunoverColors.route.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(
                color: RunoverColors.route.withValues(alpha: 0.34),
              ),
            ),
            child: const Icon(
              Icons.directions_run_rounded,
              size: 36,
              color: RunoverColors.routeDark,
            ),
          ),
          const SizedBox(height: 10),
          RichText(
            textAlign: TextAlign.center,
            text: const TextSpan(
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                color: RunoverColors.paper,
              ),
              children: [
                TextSpan(text: 'RUN'),
                TextSpan(
                  text: 'OVER!',
                  style: TextStyle(color: RunoverColors.routeDark),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Domine territórios correndo.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: RunoverColors.paper.withValues(alpha: 0.62),
              fontSize: 13,
            ),
          ),
        ],
      );

  Widget get _emailField => TextField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.username, AutofillHints.email],
        style: const TextStyle(color: RunoverColors.ink),
        decoration: InputDecoration(
          labelText: 'E-mail',
          hintText: 'Seu e-mail',
          prefixIcon: const Icon(Icons.mail_outline_rounded),
          filled: true,
          fillColor: RunoverColors.paper,
          labelStyle: const TextStyle(color: RunoverColors.ink),
          hintStyle: TextStyle(color: RunoverColors.ink.withValues(alpha: 0.55)),
          prefixIconColor: RunoverColors.territory,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: RunoverColors.territory.withValues(alpha: 0.18),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: RunoverColors.territory, width: 1.7),
          ),
        ),
      );

  Widget get _passwordField => TextField(
        controller: _passwordCtrl,
        obscureText: !_showPassword,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.password],
        style: const TextStyle(color: RunoverColors.ink),
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'Senha',
          hintText: 'Sua senha',
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(
            tooltip: _showPassword ? 'Ocultar senha' : 'Mostrar senha',
            onPressed: () => setState(() => _showPassword = !_showPassword),
            icon: Icon(
              _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            ),
          ),
          filled: true,
          fillColor: RunoverColors.paper,
          labelStyle: const TextStyle(color: RunoverColors.ink),
          hintStyle: TextStyle(color: RunoverColors.ink.withValues(alpha: 0.55)),
          prefixIconColor: RunoverColors.territory,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: RunoverColors.territory.withValues(alpha: 0.18),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: RunoverColors.territory, width: 1.7),
          ),
        ),
      );

  Widget get _accountOptions => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            value: _rememberEmail,
            onChanged: (value) async {
              setState(() => _rememberEmail = value ?? false);
              await _persistRememberedEmail();
            },
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            visualDensity: VisualDensity.compact,
            activeColor: RunoverColors.route,
            checkColor: Colors.white,
            side: BorderSide(color: RunoverColors.paper.withValues(alpha: 0.6)),
            title: Text(
              'Lembrar e-mail',
              style: TextStyle(
                color: RunoverColors.paper.withValues(alpha: 0.9),
                fontSize: 13,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
              ),
              style: TextButton.styleFrom(
                foregroundColor: RunoverColors.routeDark,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              child: const Text('Esqueceu a senha?'),
            ),
          ),
        ],
      );

  Widget get _errorMessage => Container(
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFFFB4AB), fontSize: 13),
              ),
            ),
          ],
        ),
      );

  Widget get _loginButton => SizedBox(
        height: 52,
        child: FilledButton(
          onPressed: _loading ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: RunoverColors.route,
            foregroundColor: Colors.white,
            disabledBackgroundColor: RunoverColors.route.withValues(alpha: 0.55),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          child: _loading
              ? const SizedBox(
                  width: 21,
                  height: 21,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Entrar'),
        ),
      );

  Widget get _createAccount => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Novo por aqui?',
            style: TextStyle(color: RunoverColors.paper.withValues(alpha: 0.76)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RegisterScreen()),
            ),
            style: TextButton.styleFrom(
              foregroundColor: RunoverColors.paper,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: const Text('Criar conta'),
          ),
        ],
      );

  Widget get _termsNotice => TextButton(
        onPressed: _openTerms,
        style: TextButton.styleFrom(
          foregroundColor: RunoverColors.paper.withValues(alpha: 0.62),
          textStyle: const TextStyle(fontSize: 12),
          padding: const EdgeInsets.symmetric(vertical: 4),
        ),
        child: const Text(
          'Ao continuar, você concorda com os Termos de Uso e a Política de Privacidade.',
          textAlign: TextAlign.center,
        ),
      );
}


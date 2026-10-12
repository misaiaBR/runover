import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../state/app_state.dart';

/// O portão do cadastro: a conta existe, mas só abre com o código que chegou
/// no e-mail. É a única tela que entrega a primeira sessão de uma conta nova.
class EmailConfirmationScreen extends StatefulWidget {
  const EmailConfirmationScreen({
    super.key,
    required this.email,
    this.expiresInMinutes,
    this.resendAfterSeconds,
  });

  final String email;

  /// Ambos vêm do servidor. Quando faltam (resposta sem o campo), a tela não
  /// mostra contagem em vez de inventar um tempo próprio.
  final int? expiresInMinutes;
  final int? resendAfterSeconds;

  @override
  State<EmailConfirmationScreen> createState() =>
      _EmailConfirmationScreenState();
}

class _EmailConfirmationScreenState extends State<EmailConfirmationScreen> {
  static const _codeLength = 12;

  final _codeCtrl = TextEditingController();
  Timer? _ticker;
  bool _loading = false;
  bool _resending = false;
  int _waitSeconds = 0;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _waitSeconds = widget.resendAfterSeconds ?? 0;
    _startTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _codeCtrl.dispose();
    super.dispose();
  }

  /// Contagem do reenvio, sempre a partir do que o servidor acabou de responder.
  void _startTicker() {
    _ticker?.cancel();
    if (_waitSeconds <= 0) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_waitSeconds > 0) {
          _waitSeconds--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(
        () => _error =
            'Digite o código que enviamos para ${widget.email}.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context
          .read<AppState>()
          .confirmEmail(email: widget.email, code: code);
      // A porta abriu: volta para a primeira rota, que agora mostra o app.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível conectar ao servidor.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await context.read<AppState>().api.resendVerification(
        widget.email,
      );
      if (!mounted) return;
      setState(() {
        _message = result.message;
        _waitSeconds = result.resendAfterSeconds ?? 0;
        _startTicker();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível conectar ao servidor.');
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar e-mail')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Enviamos um código de confirmação para ${widget.email}.',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sem ele a conta não entra no aplicativo. '
                    'Confira também a caixa de spam.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (widget.expiresInMinutes != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'O código expira em ${widget.expiresInMinutes} minutos. '
                      'Depois disso, peça um novo.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_message != null) ...[
                    Text(
                      _message!,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _codeCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(_codeLength),
                    ],
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Código recebido por e-mail',
                      hintText: '12 números',
                    ),
                  ),
                  const SizedBox(height: 16),
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
                        : const Text('Entrar'),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed:
                          _resending || _waitSeconds > 0 ? null : _resend,
                      child: Text(
                        _waitSeconds > 0
                            ? 'Reenviar código em ${_waitSeconds}s'
                            : 'Reenviar código',
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Usar outro e-mail'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

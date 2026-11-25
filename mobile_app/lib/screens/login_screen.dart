import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/forms.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _username;
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final session = context.read<Session>();
    _username = TextEditingController(text: session.lastUsername);
    _error = session.signOutReason;
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = context.read<Session>();
    try {
      await session.login(_username.text, _password.text);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseServer() async {
    final session = context.read<Session>();
    final options = [
      for (final s in AppConfig.servers) Option<String>(s.baseUrl, s.label, subtitle: s.baseUrl, icon: Icons.dns_rounded),
      const Option<String>('__custom__', 'Custom address…', icon: Icons.edit_rounded),
    ];
    final picked = await showOptionsSheet<String>(context,
        title: 'Portal server', options: options, selected: session.baseUrl);
    if (picked == null || !mounted) return;
    if (picked.value == '__custom__') {
      final url = await _askCustomUrl(session.baseUrl);
      if (url == null || !mounted) return;
      await session.setServer(url);
    } else {
      await session.setServer(picked.value);
    }
    if (mounted) setState(() {});
  }

  Future<String?> _askCustomUrl(String current) {
    final ctrl = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Server address'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: appInput('https://example.com', icon: Icons.link_rounded),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final v = ctrl.text.trim();
              final uri = Uri.tryParse(v);
              if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || uri.host.isEmpty) return;
              Navigator.of(ctx).pop(v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final size = MediaQuery.sizeOf(context);
    final compact = size.height < 640;
    final host = Uri.tryParse(session.baseUrl)?.host ?? session.baseUrl;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // brand gradient behind the top part of the page
          Container(
            height: size.height * (compact ? 0.36 : 0.42),
            decoration: const BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: compact ? 8 : 24),
                      Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: compact ? 220 : 280),
                          child: Image.asset('assets/images/logo_white.png', fit: BoxFit.contain),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'TIMESHEET',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.overlayWhite70, letterSpacing: 6, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      SizedBox(height: compact ? 20 : 32),
                      AppCard(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Welcome back',
                                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text)),
                              const SizedBox(height: 4),
                              const Text('Sign in with your portal account',
                                  style: TextStyle(color: AppColors.muted, fontSize: 14)),
                              const SizedBox(height: 22),
                              if (_error != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: AppColors.dangerBg, borderRadius: BorderRadius.circular(12)),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(_error!,
                                            style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              TextFormField(
                                controller: _username,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                enableSuggestions: false,
                                keyboardType: TextInputType.text,
                                autofillHints: const [AutofillHints.username],
                                decoration: appInput('Username', icon: Icons.person_outline_rounded),
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your username' : null,
                                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _password,
                                focusNode: _passwordFocus,
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.password],
                                decoration: appInput(
                                  'Password',
                                  icon: Icons.lock_outline_rounded,
                                  suffix: IconButton(
                                    tooltip: _obscure ? 'Show password' : 'Hide password',
                                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                    onPressed: () => setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                                onFieldSubmitted: (_) => _submit(),
                              ),
                              const SizedBox(height: 22),
                              ElevatedButton(
                                onPressed: _busy ? null : _submit,
                                child: _busy
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                                    : const Text('Sign in'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: TextButton.icon(
                          onPressed: _busy ? null : _chooseServer,
                          icon: const Icon(Icons.dns_outlined, size: 18),
                          label: Text('Server: $host', overflow: TextOverflow.ellipsis),
                          style: TextButton.styleFrom(foregroundColor: AppColors.muted),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text('© Smart System — Partner in Performance',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.subtle, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

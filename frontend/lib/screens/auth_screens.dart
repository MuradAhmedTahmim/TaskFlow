import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_provider.dart';

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Shared two-panel layout for login and registration.
class _AuthLayout extends StatelessWidget {
  const _AuthLayout({required this.title, required this.subtitle, required this.child});
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!wide) ...[
                Icon(Icons.task_alt, size: 44, color: scheme.primary),
                const SizedBox(height: 12),
              ],
              Text(title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: wide ? TextAlign.start : TextAlign.center),
              const SizedBox(height: 6),
              Text(subtitle,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                  textAlign: wide ? TextAlign.start : TextAlign.center),
              const SizedBox(height: 28),
              child,
            ],
          ),
        ),
      ),
    );
    if (!wide) return Scaffold(body: SafeArea(child: form));
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF4338CA), Color(0xFF6366F1), Color(0xFF0EA5E9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(56),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.task_alt, color: Colors.white, size: 32),
                    SizedBox(width: 10),
                    Text('TaskFlow', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
                  ]),
                  const Spacer(),
                  const Text('Smart Task and\nProject Management',
                      style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, height: 1.15)),
                  const SizedBox(height: 16),
                  Text('Organize projects, track tasks and deadlines,\nand see your progress at a glance.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 17, height: 1.5)),
                  const SizedBox(height: 32),
                  for (final f in const [
                    (Icons.folder_copy_outlined, 'Projects with members and roles'),
                    (Icons.checklist, 'Tasks with status, priority and deadlines'),
                    (Icons.insights, 'Dashboard with progress analytics'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(children: [
                        Icon(f.$1, color: Colors.white, size: 20),
                        const SizedBox(width: 12),
                        Text(f.$2, style: const TextStyle(color: Colors.white, fontSize: 15)),
                      ]),
                    ),
                  const Spacer(),
                ],
              ),
            ),
          ),
          Expanded(child: form),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(Icons.error_outline, color: scheme.onErrorContainer),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: TextStyle(color: scheme.onErrorContainer))),
      ]),
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({required this.controller, required this.label, this.validator, this.errorText, this.onSubmitted});
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      validator: widget.validator,
      onFieldSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().login(_login.text.trim(), _password.text);
    } on ApiException catch (e) {
      setState(() => _error = e.statusCode == 401 ? 'Incorrect username/email or password.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthLayout(
      title: 'Welcome back',
      subtitle: 'Sign in to continue to your workspace.',
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) _ErrorBanner(_error!),
              TextFormField(
                controller: _login,
                autofillHints: const [AutofillHints.username, AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Username or email', prefixIcon: Icon(Icons.person_outline)),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your username or email' : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              _PasswordField(
                controller: _password,
                label: 'Password',
                validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Sign in'),
              ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text("Don't have an account?"),
                TextButton(onPressed: () => context.go('/register'), child: const Text('Create one')),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    for (final c in [_fullName, _username, _email, _password, _password2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _fieldErrors = {});
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().register(
            username: _username.text.trim(),
            email: _email.text.trim(),
            fullName: _fullName.text.trim(),
            password: _password.text,
            password2: _password2.text,
          );
    } on ApiException catch (e) {
      setState(() {
        _fieldErrors = e.fieldErrors;
        _error = e.fieldErrors.isEmpty ? e.message : null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthLayout(
      title: 'Create your account',
      subtitle: 'Start organizing your projects in minutes.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) _ErrorBanner(_error!),
            TextFormField(
              controller: _fullName,
              decoration: InputDecoration(
                  labelText: 'Full name', prefixIcon: const Icon(Icons.badge_outlined), errorText: _fieldErrors['full_name']),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _username,
              decoration: InputDecoration(
                  labelText: 'Username', prefixIcon: const Icon(Icons.alternate_email), errorText: _fieldErrors['username']),
              validator: (v) {
                if (v == null || v.trim().length < 3) return 'At least 3 characters';
                if (!RegExp(r'^[\w.@+-]+$').hasMatch(v.trim())) return 'Letters, digits and @/./+/-/_ only';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                  labelText: 'Email', prefixIcon: const Icon(Icons.mail_outline), errorText: _fieldErrors['email']),
              validator: (v) => (v == null || !_emailRe.hasMatch(v.trim())) ? 'Enter a valid email' : null,
            ),
            const SizedBox(height: 16),
            _PasswordField(
              controller: _password,
              label: 'Password',
              errorText: _fieldErrors['password'],
              validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
            ),
            const SizedBox(height: 16),
            _PasswordField(
              controller: _password2,
              label: 'Confirm password',
              errorText: _fieldErrors['password2'],
              validator: (v) => v != _password.text ? 'Passwords do not match' : null,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create account'),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('Already have an account?'),
              TextButton(onPressed: () => context.go('/login'), child: const Text('Sign in')),
            ]),
          ],
        ),
      ),
    );
  }
}

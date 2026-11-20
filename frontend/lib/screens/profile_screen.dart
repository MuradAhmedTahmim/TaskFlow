import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_provider.dart';
import '../widgets/app_shell.dart';
import '../widgets/common.dart';

/// Asks for the password, then calls [onConfirm]. Pops `true` on success.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.onConfirm});
  final Future<void> Function(String password) onConfirm;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password to confirm');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm(_password.text);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.fieldErrors['password'] ?? e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('This permanently deletes your account and every project you own. It cannot be undone.'),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            enabled: !_busy,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(labelText: 'Current password', errorText: _error),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: error, foregroundColor: Theme.of(context).colorScheme.onError),
          child: Text(_busy ? 'Deleting…' : 'Delete account'),
        ),
      ],
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _pwForm = GlobalKey<FormState>();
  late final TextEditingController _fullName, _username, _email, _jobTitle, _bio;
  final _oldPw = TextEditingController();
  final _newPw = TextEditingController();
  final _newPw2 = TextEditingController();
  bool _saving = false;
  bool _savingPw = false;
  Map<String, String> _errors = {};
  Map<String, String> _pwErrors = {};

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthProvider>().user!;
    _fullName = TextEditingController(text: u.fullName);
    _username = TextEditingController(text: u.username);
    _email = TextEditingController(text: u.email);
    _jobTitle = TextEditingController(text: u.jobTitle);
    _bio = TextEditingController(text: u.bio);
  }

  @override
  void dispose() {
    for (final c in [_fullName, _username, _email, _jobTitle, _bio, _oldPw, _newPw, _newPw2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _errors = {});
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await context.read<AuthProvider>().updateProfile({
        'full_name': _fullName.text.trim(),
        'username': _username.text.trim(),
        'email': _email.text.trim(),
        'job_title': _jobTitle.text.trim(),
        'bio': _bio.text.trim(),
      });
      if (mounted) showSnack(context, 'Profile saved');
    } on ApiException catch (e) {
      setState(() => _errors = e.fieldErrors);
      if (e.fieldErrors.isEmpty && mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    setState(() => _pwErrors = {});
    if (!_pwForm.currentState!.validate()) return;
    setState(() => _savingPw = true);
    try {
      await context.read<AuthProvider>().changePassword(_oldPw.text, _newPw.text);
      _oldPw.clear();
      _newPw.clear();
      _newPw2.clear();
      if (mounted) showSnack(context, 'Password changed');
    } on ApiException catch (e) {
      setState(() => _pwErrors = e.fieldErrors);
      if (e.fieldErrors.isEmpty && mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _savingPw = false);
    }
  }

  Future<void> _deleteAccount() async {
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteAccountDialog(onConfirm: auth.deleteAccount),
    );
    if (deleted == true) {
      await auth.endDeletedSession(); // router then redirects to the login page
      messenger.showSnackBar(const SnackBar(content: Text('Your account has been deleted')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) return const SizedBox.shrink();
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    final summary = Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          UserAvatar(user: user, radius: 40),
          const SizedBox(height: 12),
          Text(user.displayName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          Text('@${user.username}', style: TextStyle(color: muted)),
          if (user.jobTitle.isNotEmpty) ...[const SizedBox(height: 6), Text(user.jobTitle)],
          const SizedBox(height: 12),
          Text('Member since ${formatDate(user.dateJoined)}', style: TextStyle(color: muted, fontSize: 12.5)),
          const SizedBox(height: 16),
          OutlinedButton.icon(onPressed: () => confirmLogout(context), icon: const Icon(Icons.logout), label: const Text('Log out')),
        ]),
      ),
    );

    final profileForm = SectionCard(
      title: 'Profile information',
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(
            controller: _fullName,
            decoration: InputDecoration(labelText: 'Full name', errorText: _errors['full_name']),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _username,
            decoration: InputDecoration(labelText: 'Username', errorText: _errors['username']),
            validator: (v) => (v == null || v.trim().length < 3) ? 'At least 3 characters' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _email,
            decoration: InputDecoration(labelText: 'Email', errorText: _errors['email']),
            validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _jobTitle,
            maxLength: 100,
            decoration: InputDecoration(labelText: 'Job title', errorText: _errors['job_title']),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _bio,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            decoration: InputDecoration(labelText: 'Bio', alignLabelWithHint: true, errorText: _errors['bio']),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save changes')),
          ),
        ]),
      ),
    );

    final passwordForm = SectionCard(
      title: 'Change password',
      child: Form(
        key: _pwForm,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(
            controller: _oldPw,
            obscureText: true,
            decoration: InputDecoration(labelText: 'Current password', errorText: _pwErrors['old_password']),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _newPw,
            obscureText: true,
            decoration: InputDecoration(labelText: 'New password', errorText: _pwErrors['new_password']),
            validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _newPw2,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirm new password'),
            validator: (v) => v != _newPw.text ? 'Passwords do not match' : null,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
                onPressed: _savingPw ? null : _changePassword, child: Text(_savingPw ? 'Updating…' : 'Update password')),
          ),
        ]),
      ),
    );

    final error = Theme.of(context).colorScheme.error;
    final dangerZone = SectionCard(
      title: 'Delete account',
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              'Permanently delete your account. Projects you own are deleted with all their tasks, comments and '
              'history. In other projects you are removed and your tasks become unassigned. This cannot be undone.',
              style: TextStyle(color: muted),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _deleteAccount,
            style: OutlinedButton.styleFrom(foregroundColor: error, side: BorderSide(color: error)),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Delete account'),
          ),
        ],
      ),
    );

    return SingleChildScrollView(
      child: PagePadding(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const PageHeader(title: 'Profile', subtitle: 'Manage your account details'),
            const SizedBox(height: 20),
            if (wide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 300, child: summary),
                const SizedBox(width: 20),
                Expanded(child: profileForm),
                const SizedBox(width: 20),
                Expanded(child: passwordForm),
              ])
            else ...[
              summary,
              const SizedBox(height: 20),
              profileForm,
              const SizedBox(height: 20),
              passwordForm,
            ],
            const SizedBox(height: 20),
            dangerZone,
          ]),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/api_client.dart';
import 'auth_state.dart';

/// Sign-in for the console. One card on the page ground: username, password,
/// a button. Managers and above get in; anyone else is told so by the API.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();

  /// So a rejected password can be cleared and handed straight back to the
  /// typist, rather than left in the box for them to delete by hand.
  final FocusNode _passwordFocus = FocusNode();

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String username = _username.text.trim();
    final String password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.login(username, password);
      // Tells the browser the sign-in finished, so it offers to save the
      // password. AutofillGroup needs this; without it the hidden form is
      // left open and the fields can stop taking input.
      TextInput.finishAutofillContext();
      signedIn.value = true;
    } on ApiException catch (e) {
      TextInput.finishAutofillContext(shouldSave: false);
      // The server's own words: they carry the "one attempt left" warning
      // and how long a locked account has to wait.
      setState(() => _error = e.message);
      if (e.isAuthFailure) _resetPassword();
    } catch (_) {
      TextInput.finishAutofillContext(shouldSave: false);
      setState(
        () => _error =
            'Cannot reach the server. Check that the backend is running.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A rejected password is worth nothing, and on a touch screen deleting it
  /// by hand is a fiddle. Empty the box and put the cursor back in it, so the
  /// next attempt is just typing.
  void _resetPassword() {
    _password.clear();
    _passwordFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
                border: Border.all(color: theme.dividerColor),
              ),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // The company mark, as the sidebar carries it, centred at
                    // the head of the card. Aligned rather than bare: the
                    // Column stretches its children, which would pull this
                    // 40px badge into a full-width bar.
                    //
                    // White ground with a hairline, not the brand green: the
                    // mark itself is dark and would disappear into it.
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        width: 40,
                        height: 40,
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Image.asset(
                          'assets/logo.png',
                          fit: BoxFit.contain,
                          // A missing asset must not take the login screen
                          // down with it.
                          errorBuilder: (_, _, _) => Icon(
                            Icons.hub_outlined,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Sales console', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      'Sign in with a manager or admin account.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: VizPalette.inkMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    TextField(
                      controller: _username,
                      autofocus: true,
                      autofillHints: const <String>[AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _password,
                      focusNode: _passwordFocus,
                      obscureText: _obscure,
                      autofillHints: const <String>[AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: VizPalette.statusCritical,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in'),
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

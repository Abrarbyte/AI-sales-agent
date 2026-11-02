import 'package:flutter/material.dart';

import '../api.dart';
import '../config.dart';
import 'home_screen.dart';

/// SalesHub's login, from the Stitch design "Minimal Login - Conference
/// Room", kept in that design's own palette and typeface rather than the
/// dashboard's.
///
/// It therefore does not match the rest of the app: this screen is near-black
/// on Inter, the dashboard is navy and magenta on Hanken Grotesk. That is
/// deliberate — each screen follows the Stitch design it came from.
///
/// No `BackdropFilter` anywhere. The design frosts the card with
/// `backdrop-blur-md`, but that widget renders as a blank block on Flutter web,
/// so the same look is built from an opaque wash instead.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // The Stitch "Sentinels Enterprise" tokens, verbatim.
  static const _primary = Color(0xFFFFFFFF);      // white pill button
  static const _onPrimary = Color(0xFF0B0B0D);
  static const _onSurface = Color(0xFFFFFFFF);
  static const _onSurfaceVariant = Color(0xFFA1A1AA);
  static const _outlineVariant = Color(0x1FFFFFFF);
  static const _surfaceLowest = Color(0xFF151518);
  static const _error = Color(0xFFFF6369);

  // That design's shape scale: rounded-lg = 4px, rounded-xl = 8px.
  static const _radiusLg = 4.0;
  static const _radiusXl = 8.0;

  /// The design's typeface. Set explicitly because the app's theme now
  /// defaults to Hanken Grotesk.
  static const _font = 'Inter';

  final _username = TextEditingController();
  final _password = TextEditingController();

  /// So a rejected password can be cleared and handed straight back to the
  /// typist, rather than left in the box for them to delete by hand.
  final _passwordFocus = FocusNode();

  bool _busy = false;
  bool _obscure = true;
  String? _error_;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error_ = 'Enter your username and password to continue.');
      return;
    }

    setState(() {
      _busy = true;
      _error_ = null;
    });

    try {
      await Api.instance.login(_username.text.trim(), _password.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } on ApiException catch (e) {
      setState(() => _error_ = e.message);
      // A rejected password is worth nothing, and deleting it one-handed
      // outdoors is a fiddle. Empty the box and put the cursor back in it.
      if (e.statusCode == 401) {
        _password.clear();
        _passwordFocus.requestFocus();
      }
    } catch (_) {
      // Almost always the server not running, or the wrong address for this
      // device — say so rather than showing a raw socket error.
      setState(() => _error_ = 'Cannot reach the server at ${Config.apiBase}. '
          'Check it is running and that this device can see it.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _primary,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The photograph, darkened. `bg-primary/30` in the design.
          Image.asset(
            'assets/images/login-background.jpg',
            fit: BoxFit.cover,
            // If the asset is missing the screen must still be usable, so fall
            // back to the flat ground rather than an error box.
            errorBuilder: (context, error, stack) =>
                const ColoredBox(color: _primary),
          ),
          const ColoredBox(color: Color(0x4D000000)), // black @ 30%
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _card(),
                    ),
                  ),
                ),
                _serverLine(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The panel holding the form: a dark wash with a hairline white border.
  Widget _card() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 384), // max-w-sm
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          // `bg-primary/20` plus the blur the web cannot do; a heavier wash
          // stands in for the frosting so the white type still holds.
          color: const Color(0x59000000), // black @ 35%
          borderRadius: BorderRadius.circular(_radiusXl),
          border: Border.all(color: _onPrimary.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const SizedBox(height: 32),
            _field(
              label: 'Username',
              controller: _username,
              hint: 'Enter your username',
              icon: Icons.person_outline,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 24),
            _field(
              label: 'Password',
              controller: _password,
              hint: '••••••••',
              icon: Icons.lock_outline,
              focusNode: _passwordFocus,
              obscure: _obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              suffix: IconButton(
                iconSize: 20,
                color: _onSurfaceVariant,
                icon: Icon(_obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            if (_error_ != null) ...[
              const SizedBox(height: 16),
              _errorBanner(_error_!),
            ],
            const SizedBox(height: 24),
            _signInButton(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Column(
      children: [
        // A light badge, because the mark's R is black and this card is not.
        Container(
          width: 72,
          height: 72,
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            // Stays white: the mark itself is black.
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
        ),
        const SizedBox(height: 16),
        const Text(
          'SalesHub',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: _font,
            fontSize: 24, // headline-lg-mobile
            height: 32 / 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.24, // -0.01em
            color: _onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sign in to log your visits and leads.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: _font,
            fontSize: 14, // body-md
            height: 20 / 14,
            color: _onSurface.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }

  /// A label above the field, and a leading icon inside it.
  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    FocusNode? focusNode,
    bool obscure = false,
    Widget? suffix,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(_radiusLg)),
      borderSide: BorderSide(color: _outlineVariant),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: _font,
            fontSize: 12, // label-md
            height: 16 / 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6, // 0.05em
            color: _onSurface,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          style: const TextStyle(
              fontFamily: _font, fontSize: 14, color: _onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                fontFamily: _font,
                fontSize: 14,
                color: _onSurfaceVariant.withValues(alpha: 0.7)),
            prefixIcon: Icon(icon,
                size: 20, color: _onSurfaceVariant.withValues(alpha: 0.7)),
            suffixIcon: suffix,
            filled: true,
            fillColor: _surfaceLowest,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: border,
            enabledBorder: border,
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(_radiusLg)),
              borderSide: BorderSide(color: _primary, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  /// Errors sit on the dark card, where plain red text would not carry — so
  /// they get a solid backing of their own.
  Widget _errorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _error,
        borderRadius: BorderRadius.circular(_radiusLg),
      ),
      child: Text(
        message,
        style: const TextStyle(
            fontFamily: _font, fontSize: 13, height: 18 / 13, color: _onSurface),
      ),
    );
  }

  Widget _signInButton() {
    return SizedBox(
      // touch-target-min, raised to Android's 48dp minimum: this app is used
      // one-handed outdoors.
      height: 48,
      child: FilledButton(
        onPressed: _busy ? null : _submit,
        style: FilledButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: _onPrimary,
          disabledBackgroundColor: _primary.withValues(alpha: 0.5),
          disabledForegroundColor: _onPrimary.withValues(alpha: 0.7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusLg),
          ),
        ),
        child: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: _onPrimary),
              )
            : const Text(
                'SIGN IN',
                style: TextStyle(
                  fontFamily: _font,
                  fontSize: 12, // label-md
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2, // tracking-wider
                ),
              ),
      ),
    );
  }

  /// Which server the app is talking to — worth seeing on the login screen,
  /// since the address changes between the office Wi-Fi and a real phone.
  Widget _serverLine() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x66000000), // black @ 40%
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Server: ${Config.apiBase}',
        style: TextStyle(
          fontFamily: _font,
          fontSize: 11, // label-sm
          height: 14 / 11,
          fontWeight: FontWeight.w500,
          color: _onSurface.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

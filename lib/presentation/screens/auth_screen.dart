// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Auth Screen
// Login · Registro · Google · Invitado
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/nava_theme.dart';

class AuthScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;
  const AuthScreen({super.key, required this.onAuthenticated});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ── Guest (anonymous) ────────────────────────────────────────────────────
  Future<void> _continueAsGuest() async {
    try {
      await FirebaseAuth.instance.signInAnonymously();
      if (mounted) widget.onAuthenticated();
    } catch (e) {
      _showError('No se pudo iniciar sesión de invitado.');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'DrummerBody')),
      backgroundColor: NavaTheme.neonMagenta,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavaTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(children: [
            const SizedBox(height: 40),

            // ── Logo ────────────────────────────────────────────────────
            _Logo(),

            const SizedBox(height: 36),

            // ── Tab bar ─────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: NavaTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: NavaTheme.neonCyan.withOpacity(0.15)),
              ),
              child: TabBar(
                controller: _tab,
                indicator: BoxDecoration(
                  color: NavaTheme.neonCyan.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: NavaTheme.neonCyan, width: 1),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: NavaTheme.neonCyan,
                unselectedLabelColor: NavaTheme.textMuted,
                labelStyle: const TextStyle(
                  fontFamily: 'DrummerBody',
                  fontSize: 12,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold,
                ),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'INGRESAR'),
                  Tab(text: 'REGISTRARSE'),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Tab views ───────────────────────────────────────────────
            SizedBox(
              height: 340,
              child: TabBarView(
                controller: _tab,
                children: [
                  _LoginForm(onDone: widget.onAuthenticated,
                      onError: _showError),
                  _RegisterForm(onDone: widget.onAuthenticated,
                      onError: _showError),
                ],
              ),
            ),

            // ── Divider ─────────────────────────────────────────────────
            Row(children: [
              const Expanded(child: Divider(color: Color(0xFF2A3A4C))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('O', style: TextStyle(
                  fontFamily: 'DrummerBody', fontSize: 11,
                  color: NavaTheme.textMuted.withOpacity(0.5))),
              ),
              const Expanded(child: Divider(color: Color(0xFF2A3A4C))),
            ]),

            const SizedBox(height: 16),

            // ── Google Sign-In ───────────────────────────────────────────
            _GoogleButton(
              onDone: widget.onAuthenticated,
              onError: _showError,
            ),

            const SizedBox(height: 12),

            // ── Guest ────────────────────────────────────────────────────
            TextButton(
              onPressed: _continueAsGuest,
              child: const Text(
                'Continuar como invitado  →',
                style: TextStyle(
                  fontFamily: 'DrummerBody',
                  fontSize: 12,
                  color: NavaTheme.textMuted,
                  letterSpacing: 1,
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── Guest disclaimer ─────────────────────────────────────────
            Text(
              'El modo invitado no guarda tu progreso.\n'
              'Regístrate gratis para no perder tus avances.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DrummerBody',
                fontSize: 10,
                color: NavaTheme.textMuted.withOpacity(0.55),
                height: 1.6,
              ),
            ),

            const SizedBox(height: 32),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Logo
// ─────────────────────────────────────────────────────────────────────────────
class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: NavaTheme.surface,
          border: Border.all(color: NavaTheme.neonCyan, width: 1.5),
          boxShadow: [BoxShadow(
            color: NavaTheme.neonCyan.withOpacity(0.3),
            blurRadius: 30, spreadRadius: 2,
          )],
        ),
        child: const Icon(Icons.sports_bar_outlined,
            color: NavaTheme.neonCyan, size: 36),
      )
          .animate()
          .scale(duration: 500.ms, curve: Curves.elasticOut)
          .fadeIn(duration: 300.ms),

      const SizedBox(height: 16),

      const Text('NAVA DRUMMER', style: TextStyle(
        fontFamily: 'DrummerDisplay', fontSize: 22,
        color: NavaTheme.textPrimary, letterSpacing: 4,
        fontWeight: FontWeight.bold,
      )).animate(delay: 200.ms).fadeIn(duration: 400.ms).slideY(begin: 0.2),

      const SizedBox(height: 4),

      const Text('Aprende batería al ritmo de tus canciones',
        style: TextStyle(
          fontFamily: 'DrummerBody', fontSize: 11,
          color: NavaTheme.textMuted, letterSpacing: 1,
        ),
      ).animate(delay: 350.ms).fadeIn(duration: 400.ms),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Login Form
// ─────────────────────────────────────────────────────────────────────────────
class _LoginForm extends StatefulWidget {
  final VoidCallback      onDone;
  final void Function(String) onError;
  const _LoginForm({required this.onDone, required this.onError});
  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _email    = TextEditingController();
  final _password = TextEditingController();
  bool _loading    = false;
  bool _obscure    = true;
  bool _rememberMe = false;

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass  = _password.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      widget.onError('Completa todos los campos.');
      return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email, password: pass);
      final p = await SharedPreferences.getInstance();
      await p.setBool('remember_me', _rememberMe);
      if (mounted) widget.onDone();
    } on FirebaseAuthException catch (e) {
      widget.onError(_authError(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _Field(controller: _email,    hint: 'Correo electrónico',
          icon: Icons.email_outlined, keyboard: TextInputType.emailAddress),
      const SizedBox(height: 12),
      _Field(controller: _password, hint: 'Contraseña',
          icon: Icons.lock_outline, obscure: _obscure,
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                color: NavaTheme.textMuted, size: 18),
            onPressed: () => setState(() => _obscure = !_obscure),
          )),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _sendReset,
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          child: const Text('¿Olvidaste tu contraseña?',
              style: TextStyle(fontFamily: 'DrummerBody',
                  fontSize: 11, color: NavaTheme.neonCyan)),
        ),
      ),
      // ── Remember me ─────────────────────────────────────────────────────
      Row(children: [
        SizedBox(
          width: 24, height: 24,
          child: Checkbox(
            value: _rememberMe,
            onChanged: (v) => setState(() => _rememberMe = v ?? false),
            activeColor: NavaTheme.neonCyan,
            side: const BorderSide(color: NavaTheme.textMuted),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => setState(() => _rememberMe = !_rememberMe),
          child: const Text('Recordar sesión', style: TextStyle(
            fontFamily: 'DrummerBody', fontSize: 12,
            color: NavaTheme.textSecondary)),
        ),
      ]),
      const SizedBox(height: 16),
      _PrimaryButton(
        label: 'INGRESAR',
        loading: _loading,
        onTap: _submit,
      ),
    ]);
  }

  Future<void> _sendReset() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      widget.onError('Ingresa tu correo para recuperar la contraseña.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      widget.onError('Correo de recuperación enviado a $email');
    } catch (_) {
      widget.onError('No se pudo enviar el correo de recuperación.');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Register Form
// ─────────────────────────────────────────────────────────────────────────────
class _RegisterForm extends StatefulWidget {
  final VoidCallback          onDone;
  final void Function(String) onError;
  const _RegisterForm({required this.onDone, required this.onError});
  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  final _name     = TextEditingController();
  final _email    = TextEditingController();
  final _password = TextEditingController();
  final _confirm  = TextEditingController();
  bool _loading   = false;
  bool _obscure   = true;

  Future<void> _submit() async {
    final name  = _name.text.trim();
    final email = _email.text.trim();
    final pass  = _password.text.trim();
    final conf  = _confirm.text.trim();

    if (name.isEmpty || email.isEmpty || pass.isEmpty) {
      widget.onError('Completa todos los campos.');
      return;
    }
    if (pass != conf) {
      widget.onError('Las contraseñas no coinciden.');
      return;
    }
    if (pass.length < 6) {
      widget.onError('La contraseña debe tener al menos 6 caracteres.');
      return;
    }

    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email, password: pass);
      await cred.user?.updateDisplayName(name);
      // New registrations are always remembered
      final p = await SharedPreferences.getInstance();
      await p.setBool('remember_me', true);
      if (mounted) widget.onDone();
    } on FirebaseAuthException catch (e) {
      widget.onError(_authError(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _Field(controller: _name,     hint: 'Tu nombre',
          icon: Icons.person_outline),
      const SizedBox(height: 10),
      _Field(controller: _email,    hint: 'Correo electrónico',
          icon: Icons.email_outlined, keyboard: TextInputType.emailAddress),
      const SizedBox(height: 10),
      _Field(controller: _password, hint: 'Contraseña (mín. 6 caracteres)',
          icon: Icons.lock_outline,  obscure: _obscure,
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                color: NavaTheme.textMuted, size: 18),
            onPressed: () => setState(() => _obscure = !_obscure),
          )),
      const SizedBox(height: 10),
      _Field(controller: _confirm,  hint: 'Confirmar contraseña',
          icon: Icons.lock_outline,  obscure: _obscure),
      const SizedBox(height: 16),
      _PrimaryButton(
        label: 'CREAR CUENTA',
        loading: _loading,
        onTap: _submit,
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Google Sign-In Button
// ─────────────────────────────────────────────────────────────────────────────
class _GoogleButton extends StatefulWidget {
  final VoidCallback          onDone;
  final void Function(String) onError;
  const _GoogleButton({required this.onDone, required this.onError});
  @override
  State<_GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends State<_GoogleButton> {
  bool _loading = false;

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return; // user cancelled
      final auth = await googleUser.authentication;
      final cred = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken:     auth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(cred);
      // Google users are always remembered (they actively logged in)
      final p = await SharedPreferences.getInstance();
      await p.setBool('remember_me', true);
      if (mounted) widget.onDone();
    } catch (e) {
      widget.onError('No se pudo ingresar con Google.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _loading ? null : _signIn,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          color: NavaTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF3A4A5C)),
        ),
        child: _loading
            ? const Center(child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(
                    color: NavaTheme.neonCyan, strokeWidth: 2)))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                // Google G logo (colored squares)
                _GoogleIcon(),
                const SizedBox(width: 10),
                const Text('Continuar con Google', style: TextStyle(
                  fontFamily: 'DrummerBody', fontSize: 13,
                  color: NavaTheme.textPrimary, letterSpacing: 0.5,
                )),
              ]),
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20, height: 20,
      child: CustomPaint(painter: _GIconPainter()),
    );
  }
}

class _GIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Simple colored G icon
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    // Draw a simple colorful circle as Google logo placeholder
    final colors = [
      const Color(0xFF4285F4), // blue
      const Color(0xFF34A853), // green
      const Color(0xFFFBBC05), // yellow
      const Color(0xFFEA4335), // red
    ];
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 3;
    for (int i = 0; i < 4; i++) {
      paint.color = colors[i];
      canvas.drawArc(rect, i * 1.57, 1.57, false, paint);
    }
  }
  @override
  bool shouldRepaint(_) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String                hint;
  final IconData              icon;
  final bool                  obscure;
  final TextInputType         keyboard;
  final Widget?               suffixIcon;

  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure    = false,
    this.keyboard   = TextInputType.text,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NavaTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NavaTheme.neonCyan.withOpacity(0.15)),
      ),
      child: TextField(
        controller:     controller,
        obscureText:    obscure,
        keyboardType:   keyboard,
        style: const TextStyle(
          fontFamily: 'DrummerBody', fontSize: 13,
          color: NavaTheme.textPrimary),
        decoration: InputDecoration(
          hintText:        hint,
          hintStyle: const TextStyle(
              color: NavaTheme.textMuted, fontSize: 12),
          prefixIcon:      Icon(icon, color: NavaTheme.textMuted, size: 18),
          suffixIcon:      suffixIcon,
          border:          InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 14),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String       label;
  final bool         loading;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              NavaTheme.neonCyan,
              NavaTheme.neonCyan.withOpacity(0.75),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(
            color: NavaTheme.neonCyan.withOpacity(0.3),
            blurRadius: 12, offset: const Offset(0, 4),
          )],
        ),
        child: loading
            ? const Center(child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(
                    color: Colors.black, strokeWidth: 2)))
            : Center(child: Text(label, style: const TextStyle(
                fontFamily: 'DrummerBody', fontSize: 13,
                color: Colors.black, fontWeight: FontWeight.bold,
                letterSpacing: 2))),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper: Firebase error codes → mensajes en español
// ─────────────────────────────────────────────────────────────────────────────
String _authError(String code) {
  switch (code) {
    case 'user-not-found':      return 'No existe una cuenta con ese correo.';
    case 'wrong-password':      return 'Contraseña incorrecta.';
    case 'email-already-in-use':return 'Ya existe una cuenta con ese correo.';
    case 'weak-password':       return 'La contraseña es demasiado débil.';
    case 'invalid-email':       return 'El correo electrónico no es válido.';
    case 'user-disabled':       return 'Esta cuenta ha sido desactivada.';
    case 'too-many-requests':   return 'Demasiados intentos. Intenta más tarde.';
    case 'network-request-failed': return 'Sin conexión a internet.';
    case 'invalid-credential':  return 'Credenciales incorrectas.';
    default:                    return 'Error de autenticación ($code).';
  }
}

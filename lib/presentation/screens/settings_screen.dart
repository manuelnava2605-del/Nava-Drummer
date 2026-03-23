// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Settings Screen
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/nava_theme.dart';
import 'device_setup_screen.dart';
import 'latency_calibration_screen.dart';
import '../../core/locale_controller.dart';
import '../../core/notification_service.dart';
import '../../data/datasources/local/midi_engine.dart';
import '../../domain/entities/entities.dart';

class SettingsScreen extends StatefulWidget {
  final MidiEngine midiEngine;
  final VoidCallback onLogout;
  final void Function(MidiDevice?, DrumMapping?) onDeviceSelected;

  const SettingsScreen({
    super.key,
    required this.midiEngine,
    required this.onLogout,
    required this.onDeviceSelected,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool   _notifications = true;
  bool   _rememberMe    = false;
  String _language      = 'es';
  User?  _user;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notifications = p.getBool('notifications_enabled') ?? true;
      _rememberMe    = p.getBool('remember_me')           ?? false;
      _language      = p.getString('language')            ?? 'es';
    });
  }

  Future<void> _saveNotifications(bool v) async {
    await NotificationService.instance.setEnabled(v);
    if (mounted) setState(() => _notifications = v);
  }

  Future<void> _saveRememberMe(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('remember_me', v);
    if (mounted) setState(() => _rememberMe = v);
  }

  Future<void> _saveLanguage(String lang) async {
    await LocaleController.instance.setLanguage(lang);  // persists + notifies MaterialApp
    if (mounted) setState(() => _language = lang);
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: NavaTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cerrar sesión', style: TextStyle(
          fontFamily: 'DrummerDisplay', fontSize: 16, color: NavaTheme.textPrimary)),
        content: const Text('¿Seguro que quieres cerrar sesión?', style: TextStyle(
          fontFamily: 'DrummerBody', fontSize: 13, color: NavaTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(
              color: NavaTheme.textMuted, fontFamily: 'DrummerBody')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salir', style: TextStyle(
              color: NavaTheme.neonMagenta, fontFamily: 'DrummerBody',
              fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    final p = await SharedPreferences.getInstance();
    await p.setBool('remember_me', false);
    await FirebaseAuth.instance.signOut();
    widget.onLogout();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavaTheme.background,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(children: [
                _buildUserCard(),
                const SizedBox(height: 20),

                _buildSection('CUENTA', [
                  _buildToggle(
                    label:    'Recordar sesión',
                    value:    _rememberMe,
                    onChanged: _saveRememberMe,
                    icon:     Icons.lock_open_outlined,
                    subtitle: 'No pedir inicio de sesión al abrir la app',
                  ),
                ]),
                const SizedBox(height: 16),

                _buildSection('IDIOMA', [
                  _buildLanguagePicker(),
                ]),
                const SizedBox(height: 16),

                _buildSection('DISPOSITIVO', [
                  _buildNavItem(
                    icon:  Icons.settings_input_component_outlined,
                    label: 'Configurar batería MIDI',
                    subtitle: 'Mapping de pads y canal MIDI',
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => DeviceSetupScreen(
                        midiEngine:      widget.midiEngine,
                        onDeviceSelected: widget.onDeviceSelected,
                      ),
                    )),
                  ),
                  _buildNavItem(
                    icon:    Icons.tune_outlined,
                    label:   'Calibración de latencia',
                    subtitle: 'Ajusta el offset de audio/MIDI',
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const LatencyCalibrationScreen(),
                    )),
                  ),
                ]),
                const SizedBox(height: 16),

                _buildSection('NOTIFICACIONES', [
                  _buildToggle(
                    label:    'Recordatorios de práctica',
                    value:    _notifications,
                    onChanged: _saveNotifications,
                    icon:     Icons.notifications_outlined,
                    subtitle: 'Notificación diaria para practicar',
                  ),
                ]),
                const SizedBox(height: 16),

                _buildSection('ACERCA DE', [
                  _buildNavItem(
                    icon:  Icons.shield_outlined,
                    label: 'Política de privacidad',
                    onTap: () {},
                  ),
                  _buildNavItem(
                    icon:  Icons.article_outlined,
                    label: 'Términos de uso',
                    onTap: () {},
                  ),
                  _buildInfoItem(
                    icon:  Icons.info_outline,
                    label: 'Versión',
                    value: '1.0.0',
                  ),
                ]),
                const SizedBox(height: 28),

                _buildLogoutButton(),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(children: [
        const Text('AJUSTES', style: TextStyle(
          fontFamily: 'DrummerDisplay', fontSize: 22,
          color: NavaTheme.textPrimary, fontWeight: FontWeight.bold,
          letterSpacing: 3,
        )),
      ]),
    );
  }

  // ── User Card ─────────────────────────────────────────────────────────────

  Widget _buildUserCard() {
    final user   = _user;
    final isAnon = user?.isAnonymous ?? true;
    final name   = user?.displayName?.isNotEmpty == true
        ? user!.displayName!
        : (isAnon ? 'Invitado' : 'Drummer');
    final email  = isAnon ? 'Modo invitado' : (user?.email ?? '');
    final avatar = name.isNotEmpty ? name[0].toUpperCase() : 'D';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NavaTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NavaTheme.neonCyan.withOpacity(0.2)),
        boxShadow: [BoxShadow(
          color: NavaTheme.neonCyan.withOpacity(0.05), blurRadius: 20)],
      ),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            gradient: NavaTheme.neonGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(child: Text(avatar, style: const TextStyle(
            fontFamily: 'DrummerDisplay', fontSize: 20,
            color: NavaTheme.background, fontWeight: FontWeight.bold,
          ))),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(
              fontFamily: 'DrummerDisplay', fontSize: 14,
              color: NavaTheme.textPrimary, fontWeight: FontWeight.bold,
            )),
            const SizedBox(height: 2),
            Text(email, style: const TextStyle(
              fontFamily: 'DrummerBody', fontSize: 11, color: NavaTheme.textMuted)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isAnon
                    ? NavaTheme.textMuted.withOpacity(0.1)
                    : NavaTheme.neonCyan.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isAnon ? 'INVITADO' : 'PLAN GRATIS',
                style: TextStyle(
                  fontFamily: 'DrummerBody', fontSize: 9, letterSpacing: 1,
                  color: isAnon ? NavaTheme.textMuted : NavaTheme.neonCyan),
              ),
            ),
          ],
        )),
        if (!isAnon)
          const Icon(Icons.verified_user_outlined,
              color: NavaTheme.neonGreen, size: 22),
      ]),
    ).animate().fadeIn(duration: 400.ms);
  }

  // ── Section Container ─────────────────────────────────────────────────────

  Widget _buildSection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title, style: const TextStyle(
            fontFamily: 'DrummerBody', fontSize: 10, letterSpacing: 2,
            color: NavaTheme.neonCyan, fontWeight: FontWeight.bold,
          )),
        ),
        Container(
          decoration: BoxDecoration(
            color: NavaTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NavaTheme.neonCyan.withOpacity(0.1)),
          ),
          child: Column(children: [
            for (int i = 0; i < items.length; i++) ...[
              items[i],
              if (i < items.length - 1)
                Divider(height: 1,
                    color: NavaTheme.neonCyan.withOpacity(0.07),
                    indent: 16, endIndent: 16),
            ],
          ]),
        ),
      ],
    );
  }

  // ── Toggle Row ────────────────────────────────────────────────────────────

  Widget _buildToggle(
      {required String label,
      required bool value,
      required ValueChanged<bool> onChanged,
      required IconData icon,
      String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(children: [
        Icon(icon, color: NavaTheme.textMuted, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(
              fontFamily: 'DrummerBody', fontSize: 13,
              color: NavaTheme.textPrimary)),
            if (subtitle != null)
              Text(subtitle, style: const TextStyle(
                fontFamily: 'DrummerBody', fontSize: 10,
                color: NavaTheme.textMuted)),
          ],
        )),
        Switch(value: value, onChanged: onChanged,
            activeColor: NavaTheme.neonCyan),
      ]),
    );
  }

  // ── Language Picker ───────────────────────────────────────────────────────

  Widget _buildLanguagePicker() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        const Icon(Icons.language, color: NavaTheme.textMuted, size: 18),
        const SizedBox(width: 12),
        const Expanded(child: Text('Idioma de la app', style: TextStyle(
          fontFamily: 'DrummerBody', fontSize: 13,
          color: NavaTheme.textPrimary))),
        _LangButton(label: 'ES', selected: _language == 'es',
            onTap: () => _saveLanguage('es')),
        const SizedBox(width: 8),
        _LangButton(label: 'EN', selected: _language == 'en',
            onTap: () => _saveLanguage('en')),
      ]),
    );
  }

  // ── Nav Item ──────────────────────────────────────────────────────────────

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, color: NavaTheme.textMuted, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(
                fontFamily: 'DrummerBody', fontSize: 13,
                color: NavaTheme.textPrimary)),
              if (subtitle != null)
                Text(subtitle, style: const TextStyle(
                  fontFamily: 'DrummerBody', fontSize: 10,
                  color: NavaTheme.textMuted)),
            ],
          )),
          const Icon(Icons.chevron_right, color: NavaTheme.textMuted, size: 18),
        ]),
      ),
    );
  }

  // ── Info Item (no chevron) ────────────────────────────────────────────────

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Icon(icon, color: NavaTheme.textMuted, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(
          fontFamily: 'DrummerBody', fontSize: 13,
          color: NavaTheme.textPrimary))),
        Text(value, style: const TextStyle(
          fontFamily: 'DrummerBody', fontSize: 12,
          color: NavaTheme.textMuted)),
      ]),
    );
  }

  // ── Logout Button ─────────────────────────────────────────────────────────

  Widget _buildLogoutButton() {
    return GestureDetector(
      onTap: _logout,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: NavaTheme.neonMagenta.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NavaTheme.neonMagenta.withOpacity(0.4)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.logout, color: NavaTheme.neonMagenta, size: 18),
          const SizedBox(width: 8),
          const Text('CERRAR SESIÓN', style: TextStyle(
            fontFamily: 'DrummerBody', fontSize: 13,
            color: NavaTheme.neonMagenta, fontWeight: FontWeight.bold,
            letterSpacing: 2,
          )),
        ]),
      ),
    );
  }
}

// ── Language Button ───────────────────────────────────────────────────────────

class _LangButton extends StatelessWidget {
  final String       label;
  final bool         selected;
  final VoidCallback onTap;
  const _LangButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: selected
            ? NavaTheme.neonCyan.withOpacity(0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? NavaTheme.neonCyan
              : NavaTheme.textMuted.withOpacity(0.2)),
      ),
      child: Text(label, style: TextStyle(
        fontFamily: 'DrummerBody', fontSize: 11, letterSpacing: 1,
        color: selected ? NavaTheme.neonCyan : NavaTheme.textMuted,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      )),
    ),
  );
}

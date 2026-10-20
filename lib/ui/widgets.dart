import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/question_bank.dart';
import '../services/tts_service.dart';

const correctColor = Color(0xFF2E7D32);
const wrongColor = Color(0xFFC62828);

Color correctBg(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1B3A1E) : const Color(0xFFE8F5E9);
Color wrongBg(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? const Color(0xFF4A1C1C) : const Color(0xFFFFEBEE);

/// Maximale Inhaltsbreite auf großen Bildschirmen (Windows).
class ContentWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const ContentWidth({super.key, required this.child, this.maxWidth = 900});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}

/// Bild zur Frage; Tippen öffnet eine Vollbild-Ansicht mit Zoom.
class QuestionImage extends StatelessWidget {
  final String asset;
  final double size;
  const QuestionImage({super.key, required this.asset, this.size = 160});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              InteractiveViewer(
                maxScale: 6,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Image.asset(asset, fit: BoxFit.contain, filterQuality: FilterQuality.high),
                ),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.black87),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Image.asset(asset, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
      ),
    );
  }
}

/// Fragetext mit optionaler Zweitsprache.
class QuestionText extends StatelessWidget {
  final Question question;
  final double fontSize;
  const QuestionText({super.key, required this.question, this.fontSize = 19});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final it = app.italianQuestions;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          question.text(it),
          style: theme.textTheme.titleLarge?.copyWith(fontSize: fontSize, height: 1.35, fontWeight: FontWeight.w500),
        ),
        if (app.settings.showSecondLanguage) ...[
          const SizedBox(height: 8),
          SelectableText(
            question.text(!it),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

/// Kleine Symbolleiste für eine Frage: Vorlesen, Favorit, Notiz, Sprache.
class QuestionToolbar extends StatelessWidget {
  final Question question;
  const QuestionToolbar({super.key, required this.question});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final fav = app.isFavorite(question);
    final hasNote = app.note(question).isNotEmpty;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Text('Nr. ${question.id}', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: muted)),
        const Spacer(),
        IconButton(
          tooltip: context.tr('Vorlesen', 'Leggi ad alta voce'),
          icon: const Icon(Icons.volume_up_outlined),
          onPressed: () => TtsService.speak(
            question.text(app.italianQuestions),
            italian: app.italianQuestions,
            rate: app.local.ttsRate,
          ),
        ),
        IconButton(
          tooltip: context.tr('Andere Sprache anzeigen', 'Mostra l\'altra lingua'),
          icon: Icon(Icons.translate, color: app.settings.showSecondLanguage ? Theme.of(context).colorScheme.primary : null),
          onPressed: () => app.updateSettings((s) => s.showSecondLanguage = !s.showSecondLanguage),
        ),
        IconButton(
          tooltip: context.tr('Notiz', 'Nota'),
          icon: Icon(hasNote ? Icons.sticky_note_2 : Icons.sticky_note_2_outlined,
              color: hasNote ? Colors.amber.shade700 : null),
          onPressed: () => editNote(context, question),
        ),
        IconButton(
          tooltip: context.tr('Favorit', 'Preferita'),
          icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Colors.amber.shade700 : null),
          onPressed: () => app.toggleFavorite(question),
        ),
      ],
    );
  }
}

Future<void> editNote(BuildContext context, Question q) async {
  final app = context.read<AppState>();
  final controller = TextEditingController(text: app.note(q));
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(app.italianUi ? 'Nota per la domanda ${q.id}' : 'Notiz zu Frage ${q.id}'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 6,
        minLines: 3,
        decoration: InputDecoration(
          hintText: app.italianUi ? 'Il tuo promemoria…' : 'Deine Eselsbrücke…',
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(app.italianUi ? 'Annulla' : 'Abbrechen')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: Text(app.italianUi ? 'Salva' : 'Speichern'),
        ),
      ],
    ),
  );
  if (result != null) app.setNote(q, result);
}

/// Ringförmige Fortschrittsanzeige mit Text in der Mitte.
class ProgressRing extends StatelessWidget {
  final double value;
  final double size;
  final Color? color;
  final Widget? center;
  final double stroke;
  const ProgressRing({super.key, required this.value, this.size = 96, this.color, this.center, this.stroke = 10});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: value.clamp(0, 1),
              strokeWidth: stroke,
              strokeCap: StrokeCap.round,
              color: c,
              backgroundColor: c.withValues(alpha: 0.15),
            ),
          ),
          ?center,
        ],
      ),
    );
  }
}

/// Farbe für einen Anteil von 0 (schlecht) bis 1 (gut).
Color scoreColor(double v) {
  if (v >= 0.85) return correctColor;
  if (v >= 0.6) return const Color(0xFFF9A825);
  return wrongColor;
}

String formatDuration(int seconds, {bool italian = false}) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return '$h h ${m.toString().padLeft(2, '0')} min';
  if (m > 0) return '$m min';
  return '${max(0, seconds)} s';
}

String formatClock(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String formatDate(DateTime d, {bool withTime = false}) {
  final date = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  if (!withTime) return date;
  return '$date, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Karte mit Titel für Übersichtsseiten.
class SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Widget? trailing;
  const SectionCard({
    super.key,
    this.title,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Row(
                  children: [
                    Expanded(child: Text(title!, style: Theme.of(context).textTheme.titleMedium)),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: 12),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Kleine Kennzahl mit Beschriftung.
class StatTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData? icon;
  final Color? color;
  const StatTile({super.key, required this.value, required this.label, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 18, color: color ?? theme.colorScheme.primary), const SizedBox(width: 6)],
            Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color)),
          ],
        ),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// Status-Punkt einer Frage (neu / falsch / lernend / gelernt).
Widget questionStatusIcon(BuildContext context, Question q) {
  final p = context.watch<AppState>().progress;
  if (p.isNew(q)) return Icon(Icons.circle_outlined, size: 18, color: Theme.of(context).colorScheme.outline);
  if (p.isError(q)) return const Icon(Icons.cancel, size: 18, color: wrongColor);
  if (p.isLearned(q)) return const Icon(Icons.check_circle, size: 18, color: correctColor);
  return const Icon(Icons.timelapse, size: 18, color: Color(0xFFF9A825));
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyState({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      );
}

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 840;

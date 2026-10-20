import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/question_bank.dart';
import '../services/ai_service.dart';
import '../services/tts_service.dart';
import 'widgets.dart';

/// Ergebnis + Erklärung nach dem Beantworten einer Frage.
class ExplanationPanel extends StatelessWidget {
  final Question question;
  final bool? userAnswer; // null = nicht beantwortet
  const ExplanationPanel({super.key, required this.question, this.userAnswer});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final correct = userAnswer == question.answer;
    final exp = app.bank.explanation(question, app.italianUi);
    final answerWord = question.answer ? context.tr('RICHTIG', 'VERO') : context.tr('FALSCH', 'FALSO');

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: userAnswer == null ? theme.colorScheme.surfaceContainerHighest : (correct ? correctBg(context) : wrongBg(context)),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (userAnswer != null)
                Icon(correct ? Icons.check_circle : Icons.cancel, color: correct ? correctColor : wrongColor),
              if (userAnswer != null) const SizedBox(width: 8),
              Expanded(
                child: Text(
                  userAnswer == null
                      ? context.tr('Lösung: $answerWord', 'Soluzione: $answerWord')
                      : correct
                          ? context.tr('Richtig! Die Aussage ist $answerWord.', 'Esatto! L\'affermazione è $answerWord.')
                          : context.tr('Leider falsch. Die Aussage ist $answerWord.',
                              'Sbagliato. L\'affermazione è $answerWord.'),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (exp.question != null || exp.group != null) ...[
            if (exp.otherLanguage)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  context.tr('(Erklärung nur auf Italienisch verfügbar)', '(Spiegazione disponibile solo in tedesco)'),
                  style: theme.textTheme.labelSmall,
                ),
              ),
            if (exp.question != null) SelectableText(exp.question!, style: theme.textTheme.bodyLarge?.copyWith(height: 1.4)),
            if (exp.group != null) ...[
              if (exp.question != null) const SizedBox(height: 8),
              _GroupNote(text: exp.group!),
            ],
          ] else
            Text(
              context.tr(
                'Für diese Frage gibt es noch keine Offline-Erklärung – sie kommt mit einem der nächsten Updates. '
                    'Bis dahin hilft dir die KI weiter:',
                'Per questa domanda non c\'è ancora una spiegazione offline – arriverà con uno dei prossimi aggiornamenti. '
                    'Nel frattempo chiedi all\'IA:',
              ),
              style: theme.textTheme.bodyMedium,
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => showAiSheet(context, question),
                icon: const Icon(Icons.auto_awesome),
                label: Text(context.tr('KI fragen', 'Chiedi all\'IA')),
              ),
              if (exp.question != null || exp.group != null)
                TextButton.icon(
                  onPressed: () => TtsService.speak(
                    [exp.question, exp.group].whereType<String>().join('\n'),
                    italian: app.italianUi && !exp.otherLanguage,
                    rate: app.local.ttsRate,
                  ),
                  icon: const Icon(Icons.volume_up_outlined),
                  label: Text(context.tr('Vorlesen', 'Leggi')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupNote extends StatelessWidget {
  final String text;
  const _GroupNote({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4))),
        ],
      ),
    );
  }
}

/// Auswahl: KI-Dienst im Browser öffnen oder (mit eigenem Gemini-Key) direkt in der App chatten.
Future<void> showAiSheet(BuildContext context, Question q) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _AiSheet(question: q),
  );
}

class _AiSheet extends StatefulWidget {
  final Question question;
  const _AiSheet({required this.question});

  @override
  State<_AiSheet> createState() => _AiSheetState();
}

class _AiSheetState extends State<_AiSheet> {
  final _messages = <AiMessage>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _loading = false;
  String? _error;
  bool _chatMode = false;

  Future<void> _ask([String? followUp]) async {
    final app = context.read<AppState>();
    if (followUp != null && followUp.trim().isNotEmpty) {
      _messages.add(AiMessage(true, followUp.trim()));
      _input.clear();
    }
    setState(() {
      _loading = true;
      _error = null;
      _chatMode = true;
    });
    try {
      final answer = await AiService.geminiChat(
        apiKey: app.local.geminiKey,
        model: app.local.geminiModel,
        question: widget.question,
        italian: app.italianUi,
        history: _messages,
      );
      _messages.add(AiMessage(false, answer));
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    }
    if (!mounted) return;
    setState(() => _loading = false);
    await Future.delayed(const Duration(milliseconds: 50));
    if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final hasKey = app.local.geminiKey.trim().isNotEmpty;
    final prompt = AiService.buildPrompt(widget.question, italian: app.italianUi);
    final preferred = aiServiceById(app.settings.aiService);

    final body = _chatMode
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ListView(
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final m in _messages) _Bubble(message: m),
                    if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text('⚠️ $_error', style: TextStyle(color: theme.colorScheme.error)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        enabled: !_loading,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _ask,
                        decoration: InputDecoration(
                          hintText: context.tr('Nachfrage stellen…', 'Fai un\'altra domanda…'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _loading ? null : () => _ask(_input.text),
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          )
        : SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr(
                    'Die Frage und die offizielle Lösung werden automatisch mitgeschickt.',
                    'La domanda e la soluzione ufficiale vengono inviate automaticamente.',
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (hasKey) ...[
                  FilledButton.icon(
                    onPressed: _ask,
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: Text(context.tr('Hier in der App erklären lassen (Gemini)', 'Spiegazione qui nell\'app (Gemini)')),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton.tonalIcon(
                  onPressed: () => _open(preferred, prompt),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(context.tr('In ${preferred.name} öffnen', 'Apri in ${preferred.name}')),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final s in aiServices.where((s) => s.id != preferred.id))
                      OutlinedButton(onPressed: () => _open(s, prompt), child: Text(s.name)),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: prompt));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(context.trNow('Frage kopiert', 'Domanda copiata')),
                          ));
                        }
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: Text(context.tr('Kopieren', 'Copia')),
                    ),
                  ],
                ),
                if (!hasKey) ...[
                  const SizedBox(height: 16),
                  Text(
                    context.tr(
                      'Tipp: Mit einem kostenlosen Gemini-Schlüssel (Einstellungen > KI) kannst du direkt in der App '
                          'chatten – inklusive Bild der Frage.',
                      'Suggerimento: con una chiave Gemini gratuita (Impostazioni > IA) puoi chattare direttamente '
                          'nell\'app, immagine compresa.',
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(context.tr('KI-Erklärung', 'Spiegazione IA'), style: theme.textTheme.titleLarge),
            ),
            Flexible(child: body),
          ],
        ),
      ),
    );
  }

  Future<void> _open(AiServiceInfo s, String prompt) async {
    final prefilled = await AiService.openInService(s, prompt);
    if (!prefilled && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.trNow(
          'Frage in die Zwischenablage kopiert – in ${s.name} einfügen.',
          'Domanda copiata negli appunti – incollala in ${s.name}.',
        )),
      ));
    }
  }
}

class _Bubble extends StatelessWidget {
  final AiMessage message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = message.fromUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 600),
        decoration: BoxDecoration(
          color: user ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: SelectableText.rich(_markdownLite(message.text, theme)),
      ),
    );
  }
}

/// Sehr einfache Darstellung von **fett** und Aufzählungen aus KI-Antworten.
TextSpan _markdownLite(String text, ThemeData theme) {
  final spans = <InlineSpan>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (RegExp(r'^\s*[*-]\s+').hasMatch(line)) line = line.replaceFirst(RegExp(r'^\s*[*-]\s+'), '• ');
    line = line.replaceFirst(RegExp(r'^#+\s*'), '');
    final parts = line.split('**');
    for (var j = 0; j < parts.length; j++) {
      spans.add(TextSpan(text: parts[j], style: j.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null));
    }
    if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
  }
  return TextSpan(style: theme.textTheme.bodyMedium?.copyWith(height: 1.4), children: spans);
}

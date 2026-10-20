import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/progress.dart';
import '../data/user_data.dart';
import 'learn_tab.dart';
import 'quiz_screen.dart';
import 'question_list_screen.dart';
import 'widgets.dart';

// Farbenblind-sichere Reihenfolge (Okabe-Ito): Blau für richtig, Orange für falsch.
Color _seriesA(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFF56B4E9) : const Color(0xFF0072B2);
const _seriesB = Color(0xFFE69F00);

class StatsTab extends StatelessWidget {
  const StatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            tabs: [
              Tab(text: context.tr('Übersicht', 'Panoramica')),
              Tab(text: context.tr('Kapitel', 'Capitoli')),
              Tab(text: context.tr('Verlauf', 'Andamento')),
              Tab(text: context.tr('Prüfungen', 'Esami')),
            ],
          ),
          const Expanded(
            child: TabBarView(children: [_Overview(), _Chapters(), _History(), _Exams()]),
          ),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.progress;
    final theme = Theme.of(context);
    final total = app.bank.questions.length;
    final learned = p.learnedCount;
    final errors = p.errorQuestions.length;
    final learning = p.seenCount - learned - errors;
    final unseen = total - p.seenCount;
    final exams = p.exams.where((x) => x.official).toList();
    final passedExams = exams.where((x) => p.examErrors(x) <= x.maxErrors).length;
    final hardest = p.hardestQuestions(30);

    Widget segment(int value, Color color) =>
        value <= 0 ? const SizedBox.shrink() : Expanded(flex: value, child: Container(height: 18, color: color));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: context.tr('Lernstand aller $total Fragen', 'Stato di tutte le $total domande'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Row(
                        children: [
                          segment(learned, correctColor),
                          if (learned > 0 && learning > 0) const SizedBox(width: 2),
                          segment(learning, const Color(0xFFF9A825)),
                          if (learning > 0 && errors > 0) const SizedBox(width: 2),
                          segment(errors, wrongColor),
                          if (errors > 0 && unseen > 0) const SizedBox(width: 2),
                          segment(unseen, theme.colorScheme.surfaceContainerHighest),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      children: [
                        _Legend(color: correctColor, icon: Icons.check_circle, text: context.tr('$learned gelernt', '$learned imparate')),
                        _Legend(color: const Color(0xFFF9A825), icon: Icons.timelapse, text: context.tr('$learning am Lernen', '$learning in corso')),
                        _Legend(color: wrongColor, icon: Icons.cancel, text: context.tr('$errors Fehler', '$errors errori')),
                        _Legend(color: theme.colorScheme.outline, icon: Icons.circle_outlined, text: context.tr('$unseen neu', '$unseen nuove')),
                      ],
                    ),
                  ],
                ),
              ),
              SectionCard(
                child: Wrap(
                  spacing: 28,
                  runSpacing: 16,
                  children: [
                    StatTile(value: '${(p.passProbability() * 100).round()}%', label: context.tr('Bestehens-Chance', 'Probabilità di promozione'), icon: Icons.emoji_events_outlined),
                    StatTile(value: '${p.totalAnswers}', label: context.tr('Antworten gesamt', 'Risposte totali'), icon: Icons.question_answer_outlined),
                    StatTile(value: p.totalAnswers == 0 ? '–' : '${(p.accuracy * 100).round()}%', label: context.tr('Trefferquote', 'Precisione'), icon: Icons.percent),
                    StatTile(value: formatDuration(p.totalStudySeconds), label: context.tr('Lernzeit', 'Tempo di studio'), icon: Icons.schedule),
                    StatTile(value: '${p.dayStreak}', label: context.tr('Tage in Folge', 'Giorni di fila'), icon: Icons.local_fire_department),
                    StatTile(value: '${p.bestDayStreak}', label: context.tr('Beste Serie', 'Serie migliore'), icon: Icons.military_tech_outlined),
                    StatTile(value: '$passedExams/${exams.length}', label: context.tr('Simulationen bestanden', 'Simulazioni superate'), icon: Icons.assignment_turned_in_outlined),
                    StatTile(value: '${p.days.values.where((d) => d.answered > 0).length}', label: context.tr('Lerntage', 'Giorni di studio'), icon: Icons.calendar_month_outlined),
                  ],
                ),
              ),
              SectionCard(
                title: context.tr('Schwierigste Fragen', 'Domande più difficili'),
                trailing: hardest.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () => startQuiz(context, context.trNow('Schwierigste Fragen', 'Domande difficili'), hardest, immediate: true),
                        child: Text(context.tr('Üben', 'Esercitati')),
                      ),
                child: hardest.isEmpty
                    ? Text(context.tr('Noch keine Fehler – stark!', 'Ancora nessun errore – ottimo!'))
                    : Column(
                        children: [
                          for (final q in hardest.take(5))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: Text('${p.stat(q)!.wrong}×', style: theme.textTheme.titleMedium?.copyWith(color: wrongColor)),
                              title: Text(q.text(app.italianQuestions), maxLines: 2, overflow: TextOverflow.ellipsis),
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => QuestionListScreen(title: context.trNow('Schwierigste Fragen', 'Domande difficili'), questions: hardest),
                              )),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _Legend({required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16, color: color), const SizedBox(width: 4), Text(text, style: Theme.of(context).textTheme.bodySmall)],
      );
}

class _Chapters extends StatelessWidget {
  const _Chapters();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final chapters = app.progress.chapters;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr('Wissen je Kapitel (geschätzte Chance, eine Frage richtig zu beantworten). Tippen zum Üben.',
                    'Conoscenza per capitolo (probabilità stimata di rispondere bene). Tocca per esercitarti.'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final cs in chapters) _ChapterBar(stat: cs),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChapterBar extends StatelessWidget {
  final ChapterStat stat;
  const _ChapterBar({required this.stat});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final k = stat.knowledge;
    final c = stat.seen == 0 ? theme.colorScheme.outline : scoreColor(k);
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChapterScreen(chapter: stat.chapter))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${stat.chapter.id}. ${stat.chapter.name(app.italianUi)}',
                      style: theme.textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Text(stat.seen == 0 ? '–' : '${(k * 100).round()}%', style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: k, minHeight: 8, color: c, backgroundColor: c.withValues(alpha: 0.12)),
            ),
            const SizedBox(height: 2),
            Text(
              context.tr('${stat.learned}/${stat.total} gelernt · ${stat.errors} Fehler',
                  '${stat.learned}/${stat.total} imparate · ${stat.errors} errori'),
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _History extends StatefulWidget {
  const _History();

  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> {
  int _range = 14;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.progress;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final days = [for (var i = _range - 1; i >= 0; i--) DateTime(now.year, now.month, now.day).subtract(Duration(days: i))];
    final stats = [for (final d in days) p.days[dayKey(d)] ?? DayStat()];
    final maxAnswered = stats.fold<int>(0, (m, s) => max(m, s.answered));
    final maxMinutes = stats.fold<int>(0, (m, s) => max(m, (s.seconds / 60).ceil()));
    final labelEvery = _range <= 14 ? 2 : (_range <= 30 ? 5 : 10);

    Widget bottomTitle(double v, TitleMeta meta) {
      final i = v.toInt();
      if (i < 0 || i >= days.length || (days.length - 1 - i) % labelEvery != 0) return const SizedBox.shrink();
      return SideTitleWidget(
        meta: meta,
        child: Text('${days[i].day}.${days[i].month}.', style: theme.textTheme.labelSmall),
      );
    }

    final axis = FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22, interval: 1, getTitlesWidget: bottomTitle)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(meta.formattedValue, style: theme.textTheme.labelSmall)),
        ),
      ),
    );
    final grid = FlGridData(
      drawVerticalLine: false,
      getDrawingHorizontalLine: (_) => FlLine(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
    );
    final barWidth = _range <= 14 ? 14.0 : (_range <= 30 ? 7.0 : 3.0);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 7, label: Text(context.tr('7 Tage', '7 giorni'))),
                  ButtonSegment(value: 14, label: Text(context.tr('14 Tage', '14 giorni'))),
                  ButtonSegment(value: 30, label: Text(context.tr('30 Tage', '30 giorni'))),
                  ButtonSegment(value: 90, label: Text(context.tr('90 Tage', '90 giorni'))),
                ],
                selected: {_range},
                onSelectionChanged: (s) => setState(() => _range = s.first),
              ),
              const SizedBox(height: 8),
              SectionCard(
                title: context.tr('Beantwortete Fragen pro Tag', 'Domande risposte al giorno'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 16, children: [
                      _Legend(color: _seriesA(context), icon: Icons.square_rounded, text: context.tr('richtig', 'corrette')),
                      _Legend(color: _seriesB, icon: Icons.square_rounded, text: context.tr('falsch', 'sbagliate')),
                    ]),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 200,
                      child: BarChart(
                        BarChartData(
                          maxY: max(10, maxAnswered * 1.15).toDouble(),
                          titlesData: axis,
                          gridData: grid,
                          borderData: FlBorderData(show: false),
                          barTouchData: BarTouchData(
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipItem: (group, gi, rod, ri) {
                                final s = stats[group.x];
                                final d = days[group.x];
                                return BarTooltipItem(
                                  '${d.day}.${d.month}.\n${s.correct} ✓  ${s.answered - s.correct} ✗',
                                  const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                );
                              },
                            ),
                          ),
                          barGroups: [
                            for (var i = 0; i < stats.length; i++)
                              BarChartGroupData(x: i, barRods: [
                                BarChartRodData(
                                  toY: stats[i].answered.toDouble(),
                                  width: barWidth,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                  rodStackItems: stats[i].answered == 0
                                      ? []
                                      : [
                                          BarChartRodStackItem(0, stats[i].correct.toDouble(), _seriesA(context)),
                                          BarChartRodStackItem(stats[i].correct.toDouble(), stats[i].answered.toDouble(), _seriesB),
                                        ],
                                  color: _seriesA(context),
                                ),
                              ]),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SectionCard(
                title: context.tr('Trefferquote pro Tag', 'Precisione al giorno'),
                child: SizedBox(
                  height: 180,
                  child: LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: 100,
                      minX: 0,
                      maxX: (days.length - 1).toDouble(),
                      titlesData: axis,
                      gridData: grid,
                      borderData: FlBorderData(show: false),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (spots) => [
                            for (final s in spots)
                              LineTooltipItem(
                                '${days[s.x.toInt()].day}.${days[s.x.toInt()].month}.: ${s.y.round()}%',
                                const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (var i = 0; i < stats.length; i++)
                              if (stats[i].answered > 0) FlSpot(i.toDouble(), stats[i].correct * 100 / stats[i].answered),
                          ],
                          color: _seriesA(context),
                          barWidth: 2,
                          isCurved: false,
                          dotData: FlDotData(
                            getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                              radius: 4,
                              color: _seriesA(context),
                              strokeWidth: 2,
                              strokeColor: theme.colorScheme.surface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SectionCard(
                title: context.tr('Lernzeit pro Tag (Minuten)', 'Tempo di studio al giorno (minuti)'),
                child: SizedBox(
                  height: 160,
                  child: BarChart(
                    BarChartData(
                      maxY: max(10, maxMinutes * 1.15).toDouble(),
                      titlesData: axis,
                      gridData: grid,
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                            '${days[group.x].day}.${days[group.x].month}.: ${formatDuration(stats[group.x].seconds)}',
                            const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < stats.length; i++)
                          BarChartGroupData(x: i, barRods: [
                            BarChartRodData(
                              toY: stats[i].seconds / 60,
                              width: barWidth,
                              color: theme.colorScheme.primary,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ]),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Exams extends StatelessWidget {
  const _Exams();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.progress;
    final theme = Theme.of(context);
    final exams = p.exams.where((x) => x.official).take(30).toList().reversed.toList();
    if (exams.isEmpty) {
      return EmptyState(
        icon: Icons.assignment_outlined,
        text: context.tr('Mach eine Prüfungssimulation, dann siehst du hier deinen Verlauf.',
            'Fai una simulazione d\'esame per vedere qui il tuo andamento.'),
      );
    }
    final errors = [for (final x in exams) p.examErrors(x)];
    final passed = [for (var i = 0; i < exams.length; i++) if (errors[i] <= exams[i].maxErrors) i].length;
    final avg = errors.reduce((a, b) => a + b) / errors.length;
    final avgTime = exams.map((x) => x.durationSec).reduce((a, b) => a + b) ~/ exams.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                child: Wrap(
                  spacing: 28,
                  runSpacing: 12,
                  children: [
                    StatTile(value: '$passed/${exams.length}', label: context.tr('bestanden', 'superati'), icon: Icons.emoji_events_outlined),
                    StatTile(value: avg.toStringAsFixed(1), label: context.tr('Fehler im Schnitt', 'errori in media'), icon: Icons.error_outline),
                    StatTile(value: formatClock(avgTime), label: context.tr('Zeit im Schnitt', 'tempo medio'), icon: Icons.timer_outlined),
                  ],
                ),
              ),
              SectionCard(
                title: context.tr('Fehler je Simulation (Linie = Grenze 3 Fehler)', 'Errori per simulazione (linea = limite 3)'),
                child: SizedBox(
                  height: 200,
                  child: BarChart(
                    BarChartData(
                      maxY: max(6, errors.reduce(max) + 1).toDouble(),
                      gridData: FlGridData(
                        drawVerticalLine: false,
                        horizontalInterval: 1,
                        getDrawingHorizontalLine: (_) => FlLine(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                      extraLinesData: ExtraLinesData(horizontalLines: [
                        HorizontalLine(y: 3.5, color: theme.colorScheme.onSurfaceVariant, strokeWidth: 1.5, dashArray: [6, 4]),
                      ]),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            getTitlesWidget: (v, meta) => SideTitleWidget(
                              meta: meta,
                              child: Text('${v.toInt() + 1}', style: theme.textTheme.labelSmall),
                            ),
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: 1,
                            getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text('${v.toInt()}', style: theme.textTheme.labelSmall)),
                          ),
                        ),
                      ),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                            '${formatDate(DateTime.fromMillisecondsSinceEpoch(exams[group.x].start * 1000))}\n'
                            '${errors[group.x]} ${context.trNow('Fehler', 'errori')}',
                            const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < exams.length; i++)
                          BarChartGroupData(x: i, barRods: [
                            BarChartRodData(
                              toY: max(0.15, errors[i].toDouble()),
                              width: exams.length > 15 ? 8 : 16,
                              color: errors[i] <= exams[i].maxErrors ? correctColor : wrongColor,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ]),
                      ],
                    ),
                  ),
                ),
              ),
              Text(
                context.tr('Grün = bestanden, Rot = nicht bestanden. Ältere links, neuere rechts.',
                    'Verde = superato, rosso = non superato. Dai più vecchi ai più recenti.'),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

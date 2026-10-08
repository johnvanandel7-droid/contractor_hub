import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

final services = FirebaseServices.instance;

class WorkStats extends StatelessWidget {
  const WorkStats({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = services.currentUid;

    if (uid == null) {
      return Scaffold(
        appBar: AppBarWidget(),
        body: const Center(
          child: Text('You must be signed in to view work stats.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBarWidget(),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: services.clockHistory(uid, limit: 200),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading work records:\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Text('No work records yet.'),
            );
          }

          final records = docs
              .map((doc) => ClockRecord.fromFirestore(doc))
              .toList();

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Text(
                'Work Stats',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 16),

              // ─────────────────────────────────────────────
              // TOTAL HOURS
              // ─────────────────────────────────────────────

              _StatsCards(records: records),

              const SizedBox(height: 20),

              // ─────────────────────────────────────────────
              // HOURS BY JOB
              // ─────────────────────────────────────────────

              _SectionTitle(
                title: 'Hours by Job',
                icon: Icons.work_outline,
              ),

              const SizedBox(height: 10),

              HoursByJobChart(records: records),

              const SizedBox(height: 24),

              // ─────────────────────────────────────────────
              // THIS WEEK
              // ─────────────────────────────────────────────

              _SectionTitle(
                title: 'This Week',
                icon: Icons.calendar_view_week,
              ),

              const SizedBox(height: 10),

              WeeklyHoursChart(records: records),

              const SizedBox(height: 24),

              // ─────────────────────────────────────────────
              // RECENT SHIFTS
              // ─────────────────────────────────────────────

              _SectionTitle(
                title: 'Recent Shifts',
                icon: Icons.access_time,
              ),

              const SizedBox(height: 10),

              ...records
                  .take(20)
                  .map(
                    (record) => ShiftTemplate(record: record),
                  ),
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLOCK RECORD MODEL
// ═══════════════════════════════════════════════════════════════════════════

class ClockRecord {
  final String id;
  final String uid;
  final String companyName;
  final String jobSiteId;
  final String jobSiteName;
  final DateTime? clockIn;
  final DateTime? clockOut;
  final String method;
  final double? storedHours;
  final String note;

  ClockRecord({
    required this.id,
    required this.uid,
    required this.companyName,
    required this.jobSiteId,
    required this.jobSiteName,
    required this.clockIn,
    required this.clockOut,
    required this.method,
    required this.storedHours,
    required this.note,
  });

  factory ClockRecord.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();

    final clockInTimestamp = data['clockInTime'];
    final clockOutTimestamp = data['clockOutTime'];

    return ClockRecord(
      id: doc.id,
      uid: data['uid'] as String? ?? '',
      companyName: data['companyName'] as String? ?? '',
      jobSiteId: data['jobSiteId'] as String? ?? '',
      jobSiteName: data['jobSiteName'] as String? ?? 'Unknown job',
      clockIn: clockInTimestamp is Timestamp
          ? clockInTimestamp.toDate()
          : null,
      clockOut: clockOutTimestamp is Timestamp
          ? clockOutTimestamp.toDate()
          : null,
      method: data['method'] as String? ?? 'auto',
      storedHours: (data['hours'] as num?)?.toDouble(),
      note: data['note'] as String? ?? '',
    );
  }

  double get hoursWorked {
    // Manual entries already have hours saved.
    if (storedHours != null) {
      return storedHours!;
    }

    if (clockIn == null || clockOut == null) {
      return 0;
    }

    final difference = clockOut!.difference(clockIn!);

    return difference.inMinutes / 60.0;
  }

  bool get isComplete {
    return clockIn != null && clockOut != null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STATS CARDS
// ═══════════════════════════════════════════════════════════════════════════

class _StatsCards extends StatelessWidget {
  final List<ClockRecord> records;

  const _StatsCards({
    required this.records,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // Monday = start of week.
    final startOfWeek = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(
      Duration(days: now.weekday - 1),
    );

    final startOfToday = DateTime(
      now.year,
      now.month,
      now.day,
    );

    double todayHours = 0;
    double weekHours = 0;
    double totalHours = 0;

    for (final record in records) {
      final hours = record.hoursWorked;

      totalHours += hours;

      if (record.clockIn != null) {
        if (!record.clockIn!.isBefore(startOfToday)) {
          todayHours += hours;
        }

        if (!record.clockIn!.isBefore(startOfWeek)) {
          weekHours += hours;
        }
      }
    }

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            title: 'Today',
            value: '${todayHours.toStringAsFixed(1)}h',
            icon: Icons.today,
          ),
        ),

        const SizedBox(width: 8),

        Expanded(
          child: _StatCard(
            title: 'This Week',
            value: '${weekHours.toStringAsFixed(1)}h',
            icon: Icons.calendar_month,
          ),
        ),

        const SizedBox(width: 8),

        Expanded(
          child: _StatCard(
            title: 'Total',
            value: '${totalHours.toStringAsFixed(1)}h',
            icon: Icons.timer,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: kboxDecoration,
      child: Column(
        children: [
          Icon(icon, size: 25),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HOURS BY JOB CHART
// ═══════════════════════════════════════════════════════════════════════════

class HoursByJobChart extends StatelessWidget {
  final List<ClockRecord> records;

  const HoursByJobChart({
    super.key,
    required this.records,
  });

  @override
  Widget build(BuildContext context) {
    final Map<String, double> hoursByJob = {};

    for (final record in records) {
      final job = record.jobSiteName.isEmpty
          ? 'Unknown'
          : record.jobSiteName;

      hoursByJob[job] =
          (hoursByJob[job] ?? 0) + record.hoursWorked;
    }

    if (hoursByJob.isEmpty) {
      return const Text('No job data yet.');
    }

    final entries = hoursByJob.entries.toList();

    final maxHours = entries
        .map((entry) => entry.value)
        .reduce((a, b) => a > b ? a : b);

    return Container(
      height: 300,
      padding: const EdgeInsets.all(12),
      decoration: kboxDecoration,
      child: BarChart(
        BarChartData(
          maxY: maxHours == 0 ? 10 : maxHours * 1.2,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),

          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 35,
              ),
            ),

            rightTitles: const AxisTitles(
              sideTitles: SideTitles(
                showTitles: false,
              ),
            ),

            topTitles: const AxisTitles(
              sideTitles: SideTitles(
                showTitles: false,
              ),
            ),

            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 55,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();

                  if (index < 0 || index >= entries.length) {
                    return const SizedBox();
                  }

                  String name = entries[index].key;

                  if (name.length > 10) {
                    name = '${name.substring(0, 10)}...';
                  }

                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      name,
                      style: const TextStyle(fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
          ),

          barGroups: List.generate(
            entries.length,
            (index) {
              final hours = entries[index].value;

              return BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: hours,
                    width: 25,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WEEKLY HOURS CHART
// ═══════════════════════════════════════════════════════════════════════════

class WeeklyHoursChart extends StatelessWidget {
  final List<ClockRecord> records;

  const WeeklyHoursChart({
    super.key,
    required this.records,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(
      Duration(days: now.weekday - 1),
    );

    final List<double> dailyHours = List.filled(7, 0);

    for (final record in records) {
      if (record.clockIn == null) continue;

      final date = record.clockIn!;

      final difference = DateTime(
        date.year,
        date.month,
        date.day,
      ).difference(monday).inDays;

      if (difference >= 0 && difference < 7) {
        dailyHours[difference] += record.hoursWorked;
      }
    }

    final maxHours = dailyHours.reduce(
      (a, b) => a > b ? a : b,
    );

    return Container(
      height: 280,
      padding: const EdgeInsets.all(12),
      decoration: kboxDecoration,
      child: BarChart(
        BarChartData(
          maxY: maxHours == 0 ? 10 : maxHours * 1.2,
          borderData: FlBorderData(show: false),

          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 35,
              ),
            ),

            rightTitles: const AxisTitles(
              sideTitles: SideTitles(
                showTitles: false,
              ),
            ),

            topTitles: const AxisTitles(
              sideTitles: SideTitles(
                showTitles: false,
              ),
            ),

            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  const days = [
                    'Mon',
                    'Tue',
                    'Wed',
                    'Thu',
                    'Fri',
                    'Sat',
                    'Sun',
                  ];

                  final index = value.toInt();

                  if (index < 0 || index >= days.length) {
                    return const SizedBox();
                  }

                  return Text(
                    days[index],
                    style: const TextStyle(fontSize: 11),
                  );
                },
              ),
            ),
          ),

          barGroups: List.generate(
            7,
            (index) {
              return BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: dailyHours[index],
                    width: 22,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// RECENT SHIFT
// ═══════════════════════════════════════════════════════════════════════════

class ShiftTemplate extends StatelessWidget {
  final ClockRecord record;

  const ShiftTemplate({
    super.key,
    required this.record,
  });

  String _formatDate(DateTime? date) {
    if (date == null) {
      return 'Unknown date';
    }

    return '${date.month}/${date.day}/${date.year}';
  }

  String _formatTime(DateTime? date) {
    if (date == null) {
      return '--';
    }

    final hour = date.hour == 0
        ? 12
        : date.hour > 12
            ? date.hour - 12
            : date.hour;

    final minute = date.minute.toString().padLeft(2, '0');

    final period = date.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: kboxDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.work_outline),
              const SizedBox(width: 8),

              Expanded(
                child: Text(
                  record.jobSiteName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              Text(
                '${record.hoursWorked.toStringAsFixed(2)} hrs',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            _formatDate(record.clockIn),
            style: const TextStyle(
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            '${_formatTime(record.clockIn)} → ${_formatTime(record.clockOut)}',
          ),

          const SizedBox(height: 4),

          Text(
            'Method: ${record.method}',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),

          if (record.note.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              'Note: ${record.note}',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION TITLE
// ═══════════════════════════════════════════════════════════════════════════

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionTitle({
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

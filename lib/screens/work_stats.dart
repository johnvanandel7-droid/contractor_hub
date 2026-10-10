import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

final services = FirebaseServices.instance;

enum StatsPeriod { thisWeek, lastWeek, thisMonth, lastMonth, allTime }

extension StatsPeriodExtension on StatsPeriod {
  String get label {
    switch (this) {
      case StatsPeriod.thisWeek:
        return 'This Week';
      case StatsPeriod.lastWeek:
        return 'Last Week';
      case StatsPeriod.thisMonth:
        return 'This Month';
      case StatsPeriod.lastMonth:
        return 'Last Month';
      case StatsPeriod.allTime:
        return 'All Time';
    }
  }

  DateTime? get startDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (this) {
      case StatsPeriod.thisWeek:
        return today.subtract(Duration(days: today.weekday - 1));

      case StatsPeriod.lastWeek:
        return today.subtract(Duration(days: today.weekday - 1 + 7));

      case StatsPeriod.thisMonth:
        return DateTime(now.year, now.month, 1);

      case StatsPeriod.lastMonth:
        return DateTime(now.year, now.month - 1, 1);

      case StatsPeriod.allTime:
        return null;
    }
  }

  DateTime? get endDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (this) {
      case StatsPeriod.thisWeek:
        return today
            .subtract(Duration(days: today.weekday - 1))
            .add(const Duration(days: 7));

      case StatsPeriod.lastWeek:
        return today.subtract(Duration(days: today.weekday - 1));

      case StatsPeriod.thisMonth:
        return DateTime(now.year, now.month + 1, 1);

      case StatsPeriod.lastMonth:
        return DateTime(now.year, now.month, 1);

      case StatsPeriod.allTime:
        return null;
    }
  }
}

class WorkStats extends StatefulWidget {
  const WorkStats({super.key});

  @override
  State<WorkStats> createState() => _WorkStatsState();
}

class _WorkStatsState extends State<WorkStats> {
  StatsPeriod selectedPeriod = StatsPeriod.thisWeek;

  List<ClockRecord> filterRecords(List<ClockRecord> records) {
    final start = selectedPeriod.startDate;
    final end = selectedPeriod.endDate;

    return records.where((record) {
      final date = record.clockIn;

      if (date == null) return false;

      if (start != null && date.isBefore(start)) {
        return false;
      }

      if (end != null && !date.isBefore(end)) {
        return false;
      }

      return true;
    }).toList();
  }


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
            return const Center(child: CircularProgressIndicator());
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
            return const Center(child: Text('No work records yet.'));
          }

          final records = docs
              .map((doc) => ClockRecord.fromFirestore(doc))
              .toList();

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Text(
                'Work Stats',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),


              const SizedBox(height: 16),

              // Period selector
              const Text(
                'Time Period',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 8),

              DropdownButtonFormField<StatsPeriod>(
                value: selectedPeriod,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: StatsPeriod.values.map((period) {
                  return DropdownMenuItem(
                    value: period,
                    child: Text(period.label),
                  );
                }).toList(),
                onChanged: (period) {
                  if (period != null) {
                    setState(() {
                      selectedPeriod = period;
                    });
                  }
                },
              ),

              const SizedBox(height: 16),

              if (records.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('No shifts found for this period.'),
                  ),
                )
              else ...[
                _StatsCards(
                  records: records,
                  showToday: selectedPeriod == StatsPeriod.thisWeek ||
                      selectedPeriod == StatsPeriod.thisMonth ||
                      selectedPeriod == StatsPeriod.allTime,
                ),

                const SizedBox(height: 24),

                _SectionTitle(
                  title: 'Hours by Job',
                  icon: Icons.work_outline,
                ),

                const SizedBox(height: 10),

                HoursByJobChart(records: records),

                const SizedBox(height: 24),

                _SectionTitle(
                  title: selectedPeriod == StatsPeriod.allTime
                      ? 'Hours by Day of Week'
                      : 'Daily Hours — ${selectedPeriod.label}',
                  icon: Icons.calendar_view_week,
                ),

                const SizedBox(height: 10),

                WeeklyHoursChart(
                  records: records,
                  period: selectedPeriod,
                ),

                const SizedBox(height: 24),

                _SectionTitle(
                  title: 'Recent Shifts',
                  icon: Icons.access_time,
                ),

                const SizedBox(height: 10),

                ...records.take(20).map(
                  (record) => ShiftTemplate(record: record),
                ),
              ],
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
      clockIn: clockInTimestamp is Timestamp ? clockInTimestamp.toDate() : null,
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
  final bool showToday;

  const _StatsCards({
    required this.records,
    this.showToday = true,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    double todayHours = 0;
    double selectedHours = 0;

    for (final record in records) {
      selectedHours += record.hoursWorked;

      if (record.clockIn != null &&
          !record.clockIn!.isBefore(today)) {
        todayHours += record.hoursWorked;
      }
    }

    return Row(
      children: [
        if (showToday) ...[
          Expanded(
            child: _StatCard(
              title: 'Today',
              value: '${todayHours.toStringAsFixed(1)}h',
              icon: Icons.today,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: _StatCard(
            title: 'Selected Period',
            value: '${selectedHours.toStringAsFixed(1)}h',
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

  const HoursByJobChart({super.key, required this.records});

  @override
  Widget build(BuildContext context) {
    final Map<String, double> hoursByJob = {};

    for (final record in records) {
      final job = record.jobSiteName.isEmpty ? 'Unknown' : record.jobSiteName;

      hoursByJob[job] = (hoursByJob[job] ?? 0) + record.hoursWorked;
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
              sideTitles: SideTitles(showTitles: true, reservedSize: 35),
            ),

            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),

            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
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

          barGroups: List.generate(entries.length, (index) {
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
          }),
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
  final StatsPeriod period;

  const WeeklyHoursChart({
    super.key,
    required this.records,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
    final isAllTime = period == StatsPeriod.allTime;
    final isMonth = period == StatsPeriod.thisMonth ||
        period == StatsPeriod.lastMonth;

    final labels = isAllTime
        ? ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        : isMonth
            ? List.generate(31, (i) => '${i + 1}')
            : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final dailyHours = List<double>.filled(labels.length, 0);

    for (final record in records) {
      final date = record.clockIn;
      if (date == null) continue;

      final index = isAllTime
          ? date.weekday - 1
          : isMonth
              ? date.day - 1
              : date.weekday - 1;

      if (index >= 0 && index < dailyHours.length) {
        dailyHours[index] += record.hoursWorked;
      }
    }

    final maxHours = dailyHours.isEmpty
        ? 0.0
        : dailyHours.reduce((a, b) => a > b ? a : b);

    final visibleCount = isMonth
        ? (period == StatsPeriod.thisMonth
            ? DateTime.now().day
            : DateTime(
                DateTime.now().year,
                DateTime.now().month,
                0,
              ).day)
        : labels.length;

    return Container(
      height: 280,
      padding: const EdgeInsets.all(12),
      decoration: kboxDecoration,
      child: BarChart(
        BarChartData(
          maxY: maxHours == 0 ? 10 : maxHours * 1.2,
          barGroups: List.generate(visibleCount, (index) {
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: dailyHours[index],
                  width: isMonth ? 8 : 22,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          }),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 35,
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: isMonth ? 5 : 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();

                  if (index < 0 || index >= visibleCount) {
                    return const SizedBox.shrink();
                  }

                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      labels[index],
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
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

  const ShiftTemplate({super.key, required this.record});

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
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            _formatDate(record.clockIn),
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),

          const SizedBox(height: 4),

          Text(
            '${_formatTime(record.clockIn)} → ${_formatTime(record.clockOut)}',
          ),

          const SizedBox(height: 4),

          Text(
            'Method: ${record.method}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),

          if (record.note.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              'Note: ${record.note}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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

  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:flutter/material.dart';

final services = FirebaseServices.instance;

class AdministratorPanel extends StatelessWidget {
  const AdministratorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = services.currentUid;

    if (uid == null) {
      return Scaffold(
        appBar: AppBarWidget(),
        body: const Center(child: Text('You are not logged in.')),
      );
    }

    return Scaffold(
      appBar: AppBarWidget(),
      backgroundColor: Colors.grey[100],
      body: FutureBuilder<String?>(
        future: services.getUsersCompanyId(uid),
        builder: (context, companySnapshot) {
          if (companySnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (companySnapshot.hasError) {
            return Center(
              child: Text(
                'Could not load your company.',
                style: TextStyle(color: Colors.red[700]),
              ),
            );
          }

          final companyId = companySnapshot.data;

          if (companyId == null || companyId.isEmpty) {
            return const Center(
              child: Text('No company is associated with this account.'),
            );
          }

          return StreamBuilder(
            stream: services.companyStream(companyId),
            builder: (context, companyDocSnapshot) {
              if (companyDocSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (companyDocSnapshot.hasError) {
                return Center(
                  child: Text(
                    'Could not load company information.',
                    style: TextStyle(color: Colors.red[700]),
                  ),
                );
              }

              final companyDoc = companyDocSnapshot.data;

              if (companyDoc == null || !companyDoc.exists) {
                return const Center(child: Text('Company could not be found.'));
              }

              final companyData = companyDoc.data();

              if (companyData == null) {
                return const Center(
                  child: Text('Company information is empty.'),
                );
              }

              return StreamBuilder(
                stream: services.pendingJoinRequests(companyId),
                builder: (context, requestSnapshot) {
                  final pendingCount = requestSnapshot.data?.docs.length ?? 0;

                  return _AdministratorDashboard(
                    companyId: companyId,
                    companyData: companyData,
                    pendingCount: pendingCount,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _AdministratorDashboard extends StatelessWidget {
  final String companyId;
  final Map<String, dynamic> companyData;
  final int pendingCount;

  const _AdministratorDashboard({
    required this.companyId,
    required this.companyData,
    required this.pendingCount,
  });

  @override
  Widget build(BuildContext context) {
    final companyName = companyData['companyName'] as String? ?? 'Your Company';

    final plan = companyData['companyPaymentPlan'] as String? ?? 'small';

    final employees = _toInt(companyData['numberOfEmployees']);

    final employeeLimit = _toInt(companyData['numberOfAddableEmployees']);

    final images = companyData['images'] is List
        ? (companyData['images'] as List).length
        : 0;

    final imageLimit = _toInt(companyData['numberOfAddableImages']);

    final planName = _planDisplayName(plan);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              companyName,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 4),

            Text(
              'Administrator dashboard',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),

            const SizedBox(height: 20),

            _PlanUsageCard(
              planName: planName,
              employees: employees,
              employeeLimit: employeeLimit,
              images: images,
              imageLimit: imageLimit,
            ),

            const SizedBox(height: 20),

            const Text(
              'Manage company',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.05,
              children: [
                _AdminCard(
                  icon: Icons.people_alt_outlined,
                  title: 'Employees',
                  subtitle: employeeLimit > 0
                      ? '$employees / $employeeLimit seats'
                      : '$employees employees',
                  color: Colors.blue,
                  onTap: () {
                    Navigator.pushNamed(context, '/yourEmployees');
                  },
                ),

                _AdminCard(
                  icon: Icons.work_outline,
                  title: 'Jobs',
                  subtitle: 'Manage job sites',
                  color: Colors.orange,
                  onTap: () {
                    Navigator.pushNamed(context, '/yourJobs');
                  },
                ),

                _AdminCard(
                  icon: Icons.folder_outlined,
                  title: 'Files',
                  subtitle: imageLimit > 0
                      ? '$images / $imageLimit images'
                      : '$images images',
                  color: Colors.purple,
                  onTap: () {
                    Navigator.pushNamed(context, '/yourFiles');
                  },
                ),

                _AdminCard(
                  icon: Icons.money,
                  title: 'Connect to Quickbooks',
                  subtitle:
                      'connect to quickbooks and change quickbooks connection settings',
                  color: Colors.blue,
                  onTap: () {
                    Navigator.pushNamed(context, '/QuickbooksConnection');
                  },
                ),

                _AdminCard(
                  icon: Icons.person_add_alt_1,
                  title: 'Join Requests',
                  subtitle: pendingCount == 0
                      ? 'No pending requests'
                      : '$pendingCount waiting',
                  color: pendingCount > 0 ? Colors.red : Colors.green,
                  badgeCount: pendingCount,
                  onTap: () {
                    Navigator.pushNamed(context, '/joinRequests');
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            if (pendingCount > 0)
              _PendingRequestBanner(
                count: pendingCount,
                onTap: () {
                  Navigator.pushNamed(context, '/joinRequests');
                },
              ),
          ],
        ),
      ),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static String _planDisplayName(String plan) {
    switch (plan.toLowerCase()) {
      case 'medium':
        return 'Enterprise';
      case 'large':
        return 'Large Enterprise';
      case 'small':
      default:
        return 'Small Business';
    }
  }
}

class _AdminCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final int badgeCount;
  final VoidCallback onTap;

  const _AdminCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey[200]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),

                  const SizedBox(height: 14),

                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),

              if (badgeCount > 0)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badgeCount > 99 ? '99+' : badgeCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanUsageCard extends StatelessWidget {
  final String planName;
  final int employees;
  final int employeeLimit;
  final int images;
  final int imageLimit;

  const _PlanUsageCard({
    required this.planName,
    required this.employees,
    required this.employeeLimit,
    required this.images,
    required this.imageLimit,
  });

  @override
  Widget build(BuildContext context) {
    final employeeProgress = employeeLimit > 0
        ? (employees / employeeLimit).clamp(0.0, 1.0)
        : 0.0;

    final imageProgress = imageLimit > 0
        ? (images / imageLimit).clamp(0.0, 1.0)
        : 0.0;

    final employeeWarning =
        employeeLimit > 0 && employees >= employeeLimit * 0.8;

    final imageWarning = imageLimit > 0 && images >= imageLimit * 0.8;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.workspace_premium_outlined,
                  color: Colors.blue[700],
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current plan',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      planName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          _UsageRow(
            icon: Icons.people_outline,
            title: 'Employee seats',
            value: employeeLimit > 0
                ? '$employees / $employeeLimit'
                : '$employees',
            progress: employeeProgress,
            color: employeeWarning ? Colors.orange : Colors.blue,
            unlimited: employeeLimit <= 0,
          ),

          const SizedBox(height: 18),

          _UsageRow(
            icon: Icons.photo_library_outlined,
            title: 'Images',
            value: imageLimit > 0 ? '$images / $imageLimit' : '$images',
            progress: imageProgress,
            color: imageWarning ? Colors.orange : Colors.purple,
            unlimited: imageLimit <= 0,
          ),
        ],
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final double progress;
  final Color color;
  final bool unlimited;

  const _UsageRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.progress,
    required this.color,
    required this.unlimited,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: color),

            const SizedBox(width: 8),

            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),

            Text(
              unlimited ? '$value / Unlimited' : value,
              style: TextStyle(
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),

        if (!unlimited) ...[
          const SizedBox(height: 8),

          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ],
    );
  }
}

class _PendingRequestBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _PendingRequestBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.red[50],
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.notifications_active_outlined, color: Colors.red[700]),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 1
                          ? '1 employee is waiting'
                          : '$count employees are waiting',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red[800],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to review join requests.',
                      style: TextStyle(fontSize: 12, color: Colors.red[700]),
                    ),
                  ],
                ),
              ),

              Icon(Icons.chevron_right, color: Colors.red[700]),
            ],
          ),
        ),
      ),
    );
  }
}

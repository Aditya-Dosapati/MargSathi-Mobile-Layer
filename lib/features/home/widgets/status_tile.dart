import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';

class StatusTile extends StatelessWidget {
  const StatusTile({
    super.key,
    required this.label,
    required this.value,
    this.chipColor,
  });

  final String label;
  final String value;
  final Color? chipColor;

  @override
  Widget build(BuildContext context) {
    final Color color = chipColor ?? AppTheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.trending_up, color: color),
          ],
        ),
      ),
    );
  }
}

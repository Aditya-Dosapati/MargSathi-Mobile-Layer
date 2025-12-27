import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';

class SignTranslationPage extends StatelessWidget {
  const SignTranslationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign translation')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Coming soon',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Live camera and gallery sign translations will land here.',
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.notifications_outlined),
                  label: const Text('Notify me when ready'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

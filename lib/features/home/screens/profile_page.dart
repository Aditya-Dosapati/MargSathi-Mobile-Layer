import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool notificationsEnabled = true;
  bool liveUpdatesEnabled = true;
  bool compactModeEnabled = false;
  bool locationAccessEnabled = true;

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This action will be available soon.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
        ),
        backgroundColor: const Color.fromARGB(207, 83, 149, 207),
      ),
      backgroundColor: const Color.fromARGB(255, 219, 231, 248),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _HeaderCard(),
          const SizedBox(height: 14),
          _InfoCard(onAction: () => _showComingSoon(context)),
          const SizedBox(height: 14),
          _PreferencesCard(
            notificationsEnabled: notificationsEnabled,
            liveUpdatesEnabled: liveUpdatesEnabled,
            compactModeEnabled: compactModeEnabled,
            locationAccessEnabled: locationAccessEnabled,
            onChanged: (updates) {
              setState(() {
                notificationsEnabled = updates.notificationsEnabled;
                liveUpdatesEnabled = updates.liveUpdatesEnabled;
                compactModeEnabled = updates.compactModeEnabled;
                locationAccessEnabled = updates.locationAccessEnabled;
              });
            },
          ),
          const SizedBox(height: 14),
          _SupportCard(onAction: () => _showComingSoon(context)),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary, AppTheme.primary.withOpacity(0.78)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A2D6AA7),
            blurRadius: 16,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x33FFFFFF),
                ),
                child: const Center(
                  child: Text(
                    'MS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Aarav Mehta',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'aarav.mehta@example.com',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Text(
                        'Pro • Since 2024',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.white),
                onPressed: () => _showProfileSnack(context),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: const [
              _StatPill(label: 'Trips', value: '248'),
              SizedBox(width: 10),
              _StatPill(label: 'Saved', value: '42'),
              SizedBox(width: 10),
              _StatPill(label: 'Streak', value: '9 days'),
            ],
          ),
        ],
      ),
    );
  }

  void _showProfileSnack(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile editing coming soon.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.16),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white30),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.onAction});

  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F1FB),
                child: Icon(Icons.email_outlined, color: Color(0xFF2D6AA7)),
              ),
              title: const Text('Email'),
              subtitle: const Text('aarav.mehta@example.com'),
              trailing: TextButton(
                onPressed: onAction,
                child: const Text('Update'),
              ),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F1FB),
                child: Icon(Icons.phone_outlined, color: Color(0xFF2D6AA7)),
              ),
              title: const Text('Phone'),
              subtitle: const Text('+91 98765 43210'),
              trailing: TextButton(
                onPressed: onAction,
                child: const Text('Verify'),
              ),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F1FB),
                child: Icon(
                  Icons.location_on_outlined,
                  color: Color(0xFF2D6AA7),
                ),
              ),
              title: const Text('Home city'),
              subtitle: const Text('Bengaluru, India'),
              trailing: TextButton(
                onPressed: onAction,
                child: const Text('Change'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferenceUpdate {
  const _PreferenceUpdate({
    required this.notificationsEnabled,
    required this.liveUpdatesEnabled,
    required this.compactModeEnabled,
    required this.locationAccessEnabled,
  });

  final bool notificationsEnabled;
  final bool liveUpdatesEnabled;
  final bool compactModeEnabled;
  final bool locationAccessEnabled;
}

class _PreferencesCard extends StatelessWidget {
  const _PreferencesCard({
    required this.notificationsEnabled,
    required this.liveUpdatesEnabled,
    required this.compactModeEnabled,
    required this.locationAccessEnabled,
    required this.onChanged,
  });

  final bool notificationsEnabled;
  final bool liveUpdatesEnabled;
  final bool compactModeEnabled;
  final bool locationAccessEnabled;
  final ValueChanged<_PreferenceUpdate> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Notifications'),
            subtitle: const Text('Trips, parking alerts, and sign updates'),
            value: notificationsEnabled,
            activeColor: AppTheme.primary,
            onChanged: (value) {
              onChanged(
                _PreferenceUpdate(
                  notificationsEnabled: value,
                  liveUpdatesEnabled: liveUpdatesEnabled,
                  compactModeEnabled: compactModeEnabled,
                  locationAccessEnabled: locationAccessEnabled,
                ),
              );
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Live updates'),
            subtitle: const Text('Keep routes refreshed in the background'),
            value: liveUpdatesEnabled,
            activeColor: AppTheme.primary,
            onChanged: (value) {
              onChanged(
                _PreferenceUpdate(
                  notificationsEnabled: notificationsEnabled,
                  liveUpdatesEnabled: value,
                  compactModeEnabled: compactModeEnabled,
                  locationAccessEnabled: locationAccessEnabled,
                ),
              );
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Compact cards'),
            subtitle: const Text('Show tighter layouts on home and routing'),
            value: compactModeEnabled,
            activeColor: AppTheme.primary,
            onChanged: (value) {
              onChanged(
                _PreferenceUpdate(
                  notificationsEnabled: notificationsEnabled,
                  liveUpdatesEnabled: liveUpdatesEnabled,
                  compactModeEnabled: value,
                  locationAccessEnabled: locationAccessEnabled,
                ),
              );
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Location access'),
            subtitle: const Text('Allow GPS for faster routing suggestions'),
            value: locationAccessEnabled,
            activeColor: AppTheme.primary,
            onChanged: (value) {
              onChanged(
                _PreferenceUpdate(
                  notificationsEnabled: notificationsEnabled,
                  liveUpdatesEnabled: liveUpdatesEnabled,
                  compactModeEnabled: compactModeEnabled,
                  locationAccessEnabled: value,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({required this.onAction});

  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.help_outline, color: Color(0xFF2D6AA7)),
            title: const Text('Help Center'),
            subtitle: const Text('Guides, FAQs, and troubleshooting'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onAction,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.lock_outline, color: Color(0xFF2D6AA7)),
            title: const Text('Privacy & security'),
            subtitle: const Text('Manage permissions and data'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onAction,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Color(0xFFB00020)),
            title: const Text('Sign out'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onAction,
          ),
        ],
      ),
    );
  }
}

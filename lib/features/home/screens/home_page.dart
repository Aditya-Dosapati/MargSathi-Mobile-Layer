import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    const List<_InfoBannerData> banners = [
      _InfoBannerData(
        title: 'Smart Routing',
        description:
            'Get intelligent route suggestions based on real-time events and traffic conditions.',
        cta: 'Try Routing',
        icon: Icons.location_on_outlined,
        route: '/smart-routing',
        imagePath: 'assets/images/smartrouting.jpeg',
      ),
      _InfoBannerData(
        title: 'Parking Prediction',
        description:
            'Predict parking availability by area, time, and historical patterns.',
        cta: 'Check Parking',
        icon: Icons.local_parking,
        route: '/parking',
        imagePath: 'assets/images/parking.jpeg',
      ),
      _InfoBannerData(
        title: 'Sign Translation',
        description:
            'Translate traffic signs and directions to your preferred language instantly.',
        cta: 'Translate Signs',
        icon: Icons.translate,
        route: '/sign-translation',
        imagePath: 'assets/images/sign.jpeg',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MargSathi',
          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
          // selectionColor: Color.fromARGB(255, 255, 255, 255),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline, color: Colors.white),
            onPressed: () => Navigator.pushNamed(context, '/profile'),
          ),
        ],
        backgroundColor: const Color.fromARGB(207, 83, 149, 207),
      ),
      backgroundColor: Color.fromARGB(255, 219, 231, 248),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          // Color.fromARGB(55, 203, 216, 233)
          const SizedBox(height: 8),
          Text(
            'Navigate smarter.',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Smart routing, parking prediction, and live sign translations in one place.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: banners.map((item) => _InfoBanner(data: item)).toList(),
          ),
          const SizedBox(height: 18),
          // Row(
          //   children: const [
          //     Expanded(child: _StatCard(label: 'Core Features', value: '3+')),
          //     SizedBox(width: 12),
          //     Expanded(
          //       child: _StatCard(label: 'Languages Supported', value: '9+'),
          //     ),
          //     SizedBox(width: 12),
          //     Expanded(
          //       child: _StatCard(label: 'Real-time Updates', value: '24/7'),
          //     ),
          //   ],
          // ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _InfoBannerData {
  const _InfoBannerData({
    required this.title,
    required this.description,
    required this.cta,
    required this.icon,
    required this.route,
    required this.imagePath,
  });

  final String title;
  final String description;
  final String cta;
  final IconData icon;
  final String route;
  final String imagePath;
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.data});

  final _InfoBannerData data;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 480,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x262D6AA7),
              blurRadius: 14,
              offset: Offset(0, 10),
            ),
          ],
          border: Border.all(
            color: Color.fromARGB(55, 255, 255, 255).withOpacity(0.18),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.pushNamed(context, data.route),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage(data.imagePath),
                          fit: BoxFit.cover,
                          colorFilter: ColorFilter.mode(
                            Colors.black.withOpacity(0.14),
                            BlendMode.darken,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary.withOpacity(0.38),
                            Colors.black.withOpacity(0.06),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: const BoxDecoration(
                                      color: Color(0x33FFFFFF),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      data.icon,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      data.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              color: Colors.white,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          data.description,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed:
                              () => Navigator.pushNamed(context, data.route),
                          icon: const Icon(Icons.arrow_forward),
                          label: Text(data.cta),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromARGB(
                              255,
                              255,
                              255,
                              255,
                            ),
                            foregroundColor: AppTheme.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: const Color(0xFFF6F9FD),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

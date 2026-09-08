import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/device_info_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PCLinkApp());
}

class PCLinkApp extends StatelessWidget {
  const PCLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PCLink',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1), // Indigo
          brightness: Brightness.dark,
          surface: const Color(0xFF0F172A), // Slate 900
          primary: const Color(0xFF818CF8),
          secondary: const Color(0xFF38BDF8),
        ),
        scaffoldBackgroundColor: const Color(0xFF090D16),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E293B), // Slate 800
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF334155), width: 1),
          ),
        ),
        fontFamily: 'Segoe UI',
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DeviceInfoService _deviceInfoService = DeviceInfoService();
  late Future<DeviceDetails> _deviceDetailsFuture;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadDeviceDetails();
  }

  void _loadDeviceDetails() {
    setState(() {
      _deviceDetailsFuture = _deviceInfoService.getDeviceDetails();
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _isRefreshing = true;
    });
    _loadDeviceDetails();
    await _deviceDetailsFuture;
    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Color(0xFF4ADE80), size: 20),
            const SizedBox(width: 8),
            Text('$label copied to clipboard!'),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.hub_outlined, color: Color(0xFF818CF8)),
            SizedBox(width: 10),
            Text(
              'PCLink',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Refresh details',
            onPressed: _isRefreshing ? null : _refresh,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<DeviceDetails>(
        future: _deviceDetailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Detecting Device & Network details...',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load details:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            );
          }

          final details = snapshot.data!;
          final isWindows = details.platform == 'Windows';
          final isAndroid = details.platform == 'Android';

          return RefreshIndicator(
            onRefresh: _refresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Platform Header Banner
                      _buildPlatformHeader(details, isWindows, isAndroid),
                      const SizedBox(height: 20),

                      // Device ID Card (Key Metric)
                      _buildMetricCard(
                        title: 'DEVICE ID',
                        value: details.deviceId,
                        icon: Icons.fingerprint,
                        accentColor: const Color(0xFF818CF8),
                        badgeText: isWindows ? 'Machine GUID' : 'Android Hardware ID',
                        onCopy: () => _copyToClipboard(details.deviceId, 'Device ID'),
                      ),
                      const SizedBox(height: 16),

                      // IP Address Card (Key Metric)
                      _buildMetricCard(
                        title: 'IP ADDRESS (PRIMARY IPv4)',
                        value: details.primaryIp,
                        icon: Icons.wifi,
                        accentColor: const Color(0xFF38BDF8),
                        badgeText: details.primaryIp == 'Not Connected' ? 'Offline' : 'Connected',
                        badgeColor: details.primaryIp == 'Not Connected'
                            ? Colors.redAccent
                            : const Color(0xFF22C55E),
                        onCopy: () => _copyToClipboard(details.primaryIp, 'IP Address'),
                      ),
                      const SizedBox(height: 20),

                      // Network Interfaces Breakdown
                      if (details.interfaces.isNotEmpty)
                        _buildInterfacesCard(details.interfaces),
                      const SizedBox(height: 20),

                      // Device Specification & Hardware Information
                      _buildSpecsCard(details),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlatformHeader(DeviceDetails details, bool isWindows, bool isAndroid) {
    final primaryGlow = isWindows
        ? const Color(0xFF1E3A8A).withValues(alpha: 0.8)
        : const Color(0xFF065F46).withValues(alpha: 0.8);
    final borderColor = isWindows
        ? const Color(0xFF3B82F6).withValues(alpha: 0.3)
        : const Color(0xFF10B981).withValues(alpha: 0.3);
    final iconBg = isWindows
        ? Colors.blue.withValues(alpha: 0.15)
        : Colors.green.withValues(alpha: 0.15);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryGlow, const Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isWindows
                  ? Icons.laptop_windows
                  : (isAndroid ? Icons.phone_android : Icons.device_unknown),
              size: 36,
              color: isWindows ? const Color(0xFF60A5FA) : const Color(0xFF34D399),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      details.platform.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: isWindows ? const Color(0xFF93C5FD) : const Color(0xFF6EE7B7),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Target Platform',
                        style: TextStyle(fontSize: 10, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  details.deviceName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  details.osVersion,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white60,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
    required String badgeText,
    Color? badgeColor,
    required VoidCallback onCopy,
  }) {
    final effectiveBadgeColor = badgeColor ?? accentColor;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: accentColor),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: effectiveBadgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: effectiveBadgeColor.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: effectiveBadgeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: SelectableText(
                    value,
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy',
                  style: IconButton.styleFrom(
                    backgroundColor: accentColor.withValues(alpha: 0.15),
                    foregroundColor: accentColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInterfacesCard(List<NetworkAddressInfo> interfaces) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.alt_route, size: 18, color: Color(0xFFA78BFA)),
                SizedBox(width: 8),
                Text(
                  'ACTIVE NETWORK INTERFACES',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: interfaces.length,
              separatorBuilder: (context, index) =>
                  const Divider(color: Color(0xFF334155), height: 16),
              itemBuilder: (context, index) {
                final iface = interfaces[index];
                return Row(
                  children: [
                    Icon(
                      iface.interfaceName.toLowerCase().contains('wi-fi') ||
                              iface.interfaceName.toLowerCase().contains('wlan')
                          ? Icons.wifi
                          : (iface.interfaceName.toLowerCase().contains('eth') ||
                                  iface.interfaceName.toLowerCase().contains('ethernet')
                              ? Icons.settings_ethernet
                              : Icons.lan),
                      size: 18,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            iface.interfaceName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            iface.address,
                            style: const TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 13,
                              color: Color(0xFF38BDF8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16, color: Colors.white60),
                      tooltip: 'Copy IP',
                      onPressed: () => _copyToClipboard(iface.address, iface.interfaceName),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecsCard(DeviceDetails details) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: Color(0xFFFBBF24)),
                SizedBox(width: 8),
                Text(
                  'SYSTEM SPECIFICATIONS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildSpecRow('Platform Target', details.platform),
            _buildSpecRow('Operating System', details.osVersion),
            _buildSpecRow('Host / Model', details.deviceName),
            ...details.additionalDetails.entries.map(
              (entry) => _buildSpecRow(entry.key, entry.value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              key,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

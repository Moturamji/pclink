import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/universal/app_card_header.dart';
import '../../../../data/models/device_details.dart';

/// Card rendering key-value specifications and hardware parameters in a clean tabular layout.
class SpecsCard extends StatelessWidget {
  final DeviceDetails details;

  const SpecsCard({
    super.key,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final specEntries = [
      MapEntry('Platform Target', details.platform),
      MapEntry('Operating System', details.osVersion),
      MapEntry('Host / Model', details.deviceName),
      ...details.additionalDetails.entries,
    ];

    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.cardBorder, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.isDark ? 0.2 : 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCardHeader(
            icon: Icons.tune_rounded,
            iconColor: colors.primaryLight,
            title: AppStrings.systemSpecsTitle,
            subtitle: 'Device details and system info',
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: specEntries.length,
            separatorBuilder: (context, index) => Divider(
              color: colors.cardBorder,
              height: 16,
              thickness: 0.8,
            ),
            itemBuilder: (context, index) {
              final entry = specEntries[index];
              return _buildSpecRow(context, entry.key, entry.value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSpecRow(BuildContext context, String key, String value) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              key,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: SelectableText(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

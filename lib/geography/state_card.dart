import 'package:flutter/material.dart';

import '../models/us_state.dart';
import 'us_states_map_widget.dart';

/// A consistent landscape card showing a U.S. state
/// Shows US map with state highlighted (orange on light blue)
class StateCard extends StatelessWidget {
  /// The state to display
  final USState state;

  /// Whether to show the state name
  final bool showName;

  /// Background color for the card
  final Color backgroundColor;

  const StateCard({
    super.key,
    required this.state,
    this.showName = true,
    this.backgroundColor = const Color(0xFFF5F5F5),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // State name (if shown)
            if (showName) ...[
              Text(
                state.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                state.id,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 12),
            ],
            // US Map with highlighted state
            Expanded(
              child: USStatesMapWidget(
                featuredStateCode: state.id,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact version of the StateCard for list views
class StateCardCompact extends StatelessWidget {
  final USState state;
  final VoidCallback? onTap;

  const StateCardCompact({
    super.key,
    required this.state,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Small map thumbnail with highlighted state
              SizedBox(
                width: 80,
                height: 50,
                child: USStatesMapWidget(
                  featuredStateCode: state.id,
                ),
              ),
              const SizedBox(width: 12),
              // State info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Capital: ${state.capital}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              // Region badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _regionColor(state.region).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  state.region,
                  style: TextStyle(
                    fontSize: 12,
                    color: _regionColor(state.region),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _regionColor(String region) {
    switch (region.toLowerCase()) {
      case 'northeast':
        return Colors.blue;
      case 'south':
        return Colors.orange;
      case 'midwest':
        return Colors.green;
      case 'west':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}

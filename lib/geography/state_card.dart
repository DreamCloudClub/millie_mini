import 'package:flutter/material.dart';

import '../models/us_state.dart';
import 'us_map_widget.dart';
import 'state_silhouette_widget.dart';

/// A consistent landscape card showing a U.S. state
/// Left panel: State silhouette (blue) with optional flag
/// Right panel: U.S. map with state highlighted (orange)
class StateCard extends StatelessWidget {
  /// The state to display
  final USState state;

  /// Whether to show the state flag below the silhouette
  final bool showFlag;

  /// Whether to show the state name (can be hidden for quiz mode)
  final bool showName;

  /// Background color for the card
  final Color backgroundColor;

  /// Silhouette fill color
  final Color silhouetteColor;

  /// Silhouette border color
  final Color silhouetteBorderColor;

  /// Highlighted state fill color on map
  final Color highlightColor;

  /// Highlighted state border color on map
  final Color highlightBorderColor;

  /// Other states color on map
  final Color mapStateColor;

  /// Map background color
  final Color mapBackgroundColor;

  const StateCard({
    super.key,
    required this.state,
    this.showFlag = true,
    this.showName = true,
    this.backgroundColor = const Color(0xFFF5F5F5),
    this.silhouetteColor = const Color(0xFF2196F3), // Blue
    this.silhouetteBorderColor = const Color(0xFF1565C0), // Bright blue
    this.highlightColor = const Color(0xFFFF9800), // Orange
    this.highlightBorderColor = const Color(0xFFE65100), // Bright orange
    this.mapStateColor = const Color(0xFFE0E0E0), // Light grey
    this.mapBackgroundColor = const Color(0xFF9E9E9E), // Medium grey
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
        child: Row(
          children: [
            // Left panel: Silhouette + optional flag
            Expanded(
              flex: 2,
              child: _buildLeftPanel(),
            ),
            const SizedBox(width: 16),
            // Right panel: US Map
            Expanded(
              flex: 3,
              child: _buildRightPanel(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftPanel() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
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
        // State silhouette
        Expanded(
          child: StateSilhouetteWidget(
            stateId: state.id,
            fillColor: silhouetteColor,
            borderColor: silhouetteBorderColor,
          ),
        ),
        // Optional flag
        if (showFlag && state.flagAssetPath != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: Image.asset(
              state.flagAssetPath!,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                // Fallback if flag not found
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRightPanel() {
    return USMapWidget(
      highlightedStateId: state.id,
      highlightColor: highlightColor,
      highlightBorderColor: highlightBorderColor,
      stateColor: mapStateColor,
      backgroundColor: mapBackgroundColor,
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
              // State silhouette thumbnail
              SizedBox(
                width: 60,
                height: 40,
                child: StateSilhouetteWidget(
                  stateId: state.id,
                  fillColor: const Color(0xFF2196F3),
                  borderColor: const Color(0xFF1565C0),
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

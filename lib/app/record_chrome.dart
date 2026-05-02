library;

import 'package:flutter/material.dart';
import '../journey/journey.dart';
import '../recording/recorder.dart';
import 'components.dart';
import 'format.dart';
import 'theme.dart';

class Header extends StatelessWidget {
  const Header({super.key, required this.state});

  final RecorderState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, icon, color, description) = switch (state) {
      Idle() => (
        'Tripping',
        Icons.explore_outlined,
        scheme.onSurface,
        'Tripping',
      ),
      Recording(:final journey) => (
        'Recording',
        journey.mode == JourneyMode.road
            ? Icons.directions_car_rounded
            : Icons.terrain_rounded,
        scheme.primary,
        'Recording · ${modeName(journey.mode)}',
      ),
      Paused(:final journey) => (
        'Paused',
        Icons.pause_rounded,
        scheme.onSurfaceVariant,
        'Paused · ${modeName(journey.mode)}',
      ),
      Interrupted(:final journey) => (
        'Stopped',
        Icons.warning_amber_rounded,
        warningColor(context),
        'Stopped · ${modeName(journey.mode)}',
      ),
    };
    return Semantics(
      label: description,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two actions side by side, leaving more of the screen to the map; one
/// above the other when large text would not fit.
class ActionPair extends StatelessWidget {
  const ActionPair(this.first, this.second, {super.key});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(18) > 22) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, const SizedBox(height: 12), second],
      );
    }
    return Row(
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    );
  }
}

/// Switches the high-contrast look for direct sunlight; filled while on.
class HighSunButton extends StatelessWidget {
  const HighSunButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final on = lookOf(context).look == Look.highSun;
    return MapChrome(
      child: IconButton(
        onPressed: onPressed,
        isSelected: on,
        icon: const Icon(Icons.wb_sunny_outlined),
        selectedIcon: const Icon(Icons.wb_sunny),
        tooltip: on ? 'High-sun mode on' : 'High-sun mode',
      ),
    );
  }
}

class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Where to?', style: text.headlineMedium),
        const SizedBox(height: 12),
        Text(
          'Record a road journey or an expedition. Everything stays on this '
          'phone, and no internet is needed.',
          style: text.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

import 'dart:async';

/// Lance une action après un délai ; annule la précédente si nouvelle frappe.
class DebouncedRunner {
  Timer? _timer;

  void run({
    required Duration delay,
    required void Function() action,
  }) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() => _timer?.cancel();

  void dispose() => _timer?.cancel();
}

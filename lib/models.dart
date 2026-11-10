enum StepStatus { pending, running, ok, warn, fail, skipped }

class StepResult {
  final String layer;
  final String title;
  StepStatus status;
  String detail;
  String? hint;

  StepResult({
    required this.layer,
    required this.title,
    this.status = StepStatus.pending,
    this.detail = 'Menunggu...',
    this.hint,
  });
}

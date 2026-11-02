import 'package:flutter/material.dart';

class CivilDateTimeField extends StatelessWidget {
  const CivilDateTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.showTime = true,
  });
  final bool showTime;
  final String label;
  final DateTime value;
  final bool enabled;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(
                '${value.year}-${_two(value.month)}-${_two(value.day)}',
              ),
              onPressed: !enabled
                  ? null
                  : () async {
                      FocusScope.of(context).unfocus();
                      final date = await showDatePicker(
                        context: context,
                        initialDate: value,
                        firstDate: DateTime(1),
                        lastDate: DateTime(9999, 12, 31),
                      );
                      if (date != null && context.mounted) {
                        onChanged(
                          DateTime(
                            date.year,
                            date.month,
                            date.day,
                            value.hour,
                            value.minute,
                          ),
                        );
                      }
                    },
            ),
            if (showTime)
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule, size: 16),
                label: Text('${_two(value.hour)}:${_two(value.minute)}'),
                onPressed: !enabled
                    ? null
                    : () async {
                        FocusScope.of(context).unfocus();
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(value),
                        );
                        if (time != null && context.mounted) {
                          onChanged(
                            DateTime(
                              value.year,
                              value.month,
                              value.day,
                              time.hour,
                              time.minute,
                            ),
                          );
                        }
                      },
              ),
          ],
        ),
      ],
    ),
  );
}

String _two(int value) => value.toString().padLeft(2, '0');

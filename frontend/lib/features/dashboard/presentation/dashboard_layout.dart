import 'package:flutter/material.dart';

/// Dashboard 响应式布局（契约第 11 节）。
///
/// - 组件内容宽度 <600 逻辑像素：单列。
/// - >=600：双列。
/// - 内容最大宽度 1200，居中，必要时滚动。
class DashboardSectionLayout extends StatelessWidget {
  const DashboardSectionLayout({super.key, required this.sections});

  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final children = width < 600 || sections.length < 2
                  ? _singleColumn()
                  : _twoColumns();
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _singleColumn() =>
      _withGaps(sections, const SizedBox(height: 16));

  List<Widget> _twoColumns() {
    final rows = <Widget>[];
    for (var i = 0; i < sections.length; i += 2) {
      final left = Expanded(child: sections[i]);
      final right = i + 1 < sections.length
          ? Expanded(child: sections[i + 1])
          : const Expanded(child: SizedBox.shrink());
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [left, const SizedBox(width: 16), right],
        ),
      );
    }
    return _withGaps(rows, const SizedBox(height: 16));
  }

  List<Widget> _withGaps(Iterable<Widget> widgets, Widget gap) {
    final result = <Widget>[];
    var first = true;
    for (final widget in widgets) {
      if (!first) {
        result.add(gap);
      }
      result.add(widget);
      first = false;
    }
    return result;
  }
}

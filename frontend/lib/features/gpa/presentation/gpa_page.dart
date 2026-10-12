import 'package:flutter/material.dart';

import '../../academic/models/course.dart';
import '../composition/gpa_composition.dart';
import '../controllers/gpa_controller.dart';

class GpaPage extends StatefulWidget {
  const GpaPage({super.key, required this.composition});
  final GpaComposition composition;

  @override
  State<GpaPage> createState() => _GpaPageState();
}

class _GpaPageState extends State<GpaPage> {
  GpaController? _controller;
  Object? _setupError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _setupError = null);
    try {
      final controller = await widget.composition.createController();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      await controller.load();
    } catch (error) {
      if (mounted) setState(() => _setupError = error);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('GPA')),
      body: SafeArea(
        child: controller == null
            ? (_setupError == null
                  ? const Center(child: CircularProgressIndicator())
                  : Center(
                      child: TextButton(
                        onPressed: _initialize,
                        child: const Text('初始化失败，重试'),
                      ),
                    ))
            : AnimatedBuilder(
                animation: controller,
                builder: (context, _) => ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('评分上限 ${controller.scoreScaleMax}；由调用方提供'),
                    if (widget.composition.isDemo)
                      const Text(
                        '合成演示数据 · 4.0 演示规则，不代表学校官方 GPA 制度。仅存内存，重启不保留。',
                      ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey(controller.semesterId),
                      initialValue: controller.semesterId ?? '',
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '学期'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('全部学期')),
                        for (final id in {
                          ...controller.semesterIds,
                          if (controller.semesterId != null)
                            controller.semesterId!,
                        })
                          DropdownMenuItem(
                            value: id,
                            child: Text(id, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: controller.isLoading
                          ? null
                          : (id) => controller.load(
                              semesterId: id == '' ? null : id,
                            ),
                    ),
                    const SizedBox(height: 16),
                    if (controller.isLoading) const LinearProgressIndicator(),
                    if (controller.error != null) ...[
                      const Text(
                        'GPA 读取或保存失败，请重试。',
                        style: TextStyle(color: Colors.red),
                      ),
                      TextButton(
                        onPressed: controller.retry,
                        child: const Text('重试'),
                      ),
                    ],
                    if (controller.result case final result?) ...[
                      Text(
                        result.value == null
                            ? 'GPA：暂无已评分课程'
                            : 'GPA：${result.value!.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        '已评分学分：${result.gradedCredits} · 已评分课程：${result.gradedCourseCount} · 未评分：${result.missingCount}',
                      ),
                      if (controller.courses.isEmpty) const Text('暂无课程'),
                    ],
                    const SizedBox(height: 12),
                    for (final course in controller.courses)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                course.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '学期：${course.semesterId} · 学分：${course.credits}',
                              ),
                              Text(
                                course.gradePoint == null
                                    ? '绩点：未评分'
                                    : '绩点：${course.gradePoint}',
                              ),
                              TextButton(
                                key: ValueKey('edit-${course.id}'),
                                onPressed: controller.isLoading
                                    ? null
                                    : () => _edit(course, controller),
                                child: const Text('编辑成绩'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    TextButton(
                      onPressed: controller.isLoading ? null : controller.retry,
                      child: const Text('刷新'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _edit(Course course, GpaController controller) async {
    final selected = await showDialog<({double? point})>(
      context: context,
      builder: (context) =>
          _GradeDialog(course: course, scoreScaleMax: controller.scoreScaleMax),
    );
    if (selected != null && mounted) {
      await controller.setGradePoint(course.id, selected.point);
    }
  }
}

class _GradeDialog extends StatefulWidget {
  const _GradeDialog({required this.course, required this.scoreScaleMax});
  final Course course;
  final double scoreScaleMax;
  @override
  State<_GradeDialog> createState() => _GradeDialogState();
}

class _GradeDialogState extends State<_GradeDialog> {
  late final _input = TextEditingController(
    text: widget.course.gradePoint?.toString() ?? '',
  );
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('编辑课程绩点'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: TextFormField(
          controller: _input,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: '绩点（留空为未评分）',
            helperText: '0 至 ${widget.scoreScaleMax}；0 是有效成绩',
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) return null;
            final number = double.tryParse(value.trim());
            if (number == null ||
                !number.isFinite ||
                number < 0 ||
                number > widget.scoreScaleMax) {
              return '请输入范围内的有限数字';
            }
            return null;
          },
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, (
              point: _input.text.trim().isEmpty
                  ? null
                  : double.parse(_input.text.trim()),
            ));
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}

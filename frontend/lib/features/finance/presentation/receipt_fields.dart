import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/finance_record.dart';

Future<void> validateReceiptImage(Uint8List bytes) async {
  if (bytes.length > maxReceiptBytes || bytes.length < 8) {
    throw const FormatException('请选择不超过 1 MB 的 JPEG 或 PNG 图片。');
  }
  final png =
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47;
  final jpeg = bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
  if (!png && !jpeg) throw const FormatException('票据仅支持 JPEG 或 PNG。');
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      if (descriptor.width > 4096 || descriptor.height > 4096) {
        throw const FormatException('票据宽度和高度均不能超过 4096 像素。');
      }
      final codec = await descriptor.instantiateCodec();
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}

class ReceiptFields extends StatefulWidget {
  const ReceiptFields({
    super.key,
    required this.status,
    required this.receipt,
    required this.onChanged,
  });

  final ReimbursementStatus status;
  final String? receipt;
  final void Function(ReimbursementStatus status, String? receipt) onChanged;

  @override
  State<ReceiptFields> createState() => _ReceiptFieldsState();
}

class _ReceiptFieldsState extends State<ReceiptFields> {
  bool _picking = false;
  String? _error;

  Future<void> _choose() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        withData: false,
      );
      if (result == null || !mounted) return;
      final file = result.files.single;
      if (file.size > maxReceiptBytes) {
        throw const FormatException('图片不能超过 1 MB。');
      }
      final path = file.path;
      if (path == null) throw const FormatException('无法读取所选图片。');
      final bytes = await File(path)
          .openRead(0, maxReceiptBytes + 1)
          .fold<BytesBuilder>(
            BytesBuilder(),
            (buffer, chunk) => buffer..add(chunk),
          );
      final image = bytes.takeBytes();
      await validateReceiptImage(image);
      if (mounted) widget.onChanged(widget.status, base64Encode(image));
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error is FormatException
              ? error.message
              : '读取图片失败，请重新选择。',
        );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<ReimbursementStatus>(
        initialValue: widget.status,
        decoration: const InputDecoration(labelText: '报销状态'),
        items: [
          for (final state in ReimbursementStatus.values)
            DropdownMenuItem(value: state, child: Text(state.label)),
        ],
        onChanged: _picking
            ? null
            : (state) {
                if (state != null) widget.onChanged(state, widget.receipt);
              },
      ),
      if (widget.receipt case final image?) ReceiptPreview(encoded: image),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: _picking ? null : _choose,
            child: Text(_picking ? '读取中…' : '选择票据（JPEG / PNG，1 MB）'),
          ),
          if (widget.receipt != null)
            TextButton(
              onPressed: _picking
                  ? null
                  : () => widget.onChanged(widget.status, null),
              child: const Text('移除票据'),
            ),
        ],
      ),
      if (_error != null) Text(_error!),
    ],
  );
}

class ReceiptPreview extends StatelessWidget {
  const ReceiptPreview({super.key, required this.encoded});

  final String encoded;

  @override
  Widget build(BuildContext context) {
    try {
      return Image.memory(
        base64Decode(encoded),
        height: 160,
        fit: BoxFit.contain,
        cacheWidth: 700,
        errorBuilder: (_, _, _) => const Text('票据图片无法读取。'),
      );
    } on FormatException {
      return const Text('票据图片无法读取。');
    }
  }
}

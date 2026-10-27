import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:fluent_ui/fluent_ui.dart' as fluent;

bool get isIOS => defaultTargetPlatform == TargetPlatform.iOS;
bool get isWindows => defaultTargetPlatform == TargetPlatform.windows;

class AdaptiveButton extends StatelessWidget {
  const AdaptiveButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) => isIOS
      ? destructive
            ? CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: onPressed,
                child: Text(label),
              )
            : CupertinoButton(onPressed: onPressed, child: Text(label))
      : isWindows
      ? fluent.Button(onPressed: onPressed, child: Text(label))
      : material.TextButton(onPressed: onPressed, child: Text(label));
}

class AdaptiveList extends StatelessWidget {
  const AdaptiveList({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(16), children: children);
}

class AdaptiveField extends StatelessWidget {
  const AdaptiveField({
    super.key,
    this.inputKey,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboard,
    this.maxLines = 1,
  });
  final Key? inputKey;
  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboard;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final input = isIOS
        ? CupertinoTextField(
            key: inputKey,
            controller: controller,
            placeholder: hint,
            keyboardType: keyboard,
            maxLines: maxLines,
            maxLength: 500,
            padding: const EdgeInsets.all(12),
          )
        : isWindows
        ? fluent.TextBox(
            key: inputKey,
            controller: controller,
            placeholder: hint,
            keyboardType: keyboard,
            maxLines: maxLines,
            maxLength: 500,
          )
        : material.TextField(
            key: inputKey,
            controller: controller,
            decoration: material.InputDecoration(
              labelText: label,
              hintText: hint,
            ),
            keyboardType: keyboard,
            maxLines: maxLines,
            maxLength: 500,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: isIOS || isWindows
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(label), input],
            )
          : input,
    );
  }
}

class AdaptiveDialog extends StatelessWidget {
  const AdaptiveDialog({
    super.key,
    required this.title,
    this.content,
    required this.actions,
  });
  final String title;
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => isIOS
      ? CupertinoAlertDialog(
          title: Text(title),
          content: content,
          actions: actions,
        )
      : isWindows
      ? fluent.ContentDialog(
          title: Text(title),
          content: content,
          actions: actions,
        )
      : material.AlertDialog(
          title: Text(title),
          content: content,
          actions: actions,
        );
}

Future<T?> showAdaptivePrompt<T>(BuildContext context, WidgetBuilder builder) =>
    isIOS
    ? showCupertinoDialog<T>(context: context, builder: builder)
    : isWindows
    ? fluent.showDialog<T>(context: context, builder: builder)
    : material.showDialog<T>(context: context, builder: builder);

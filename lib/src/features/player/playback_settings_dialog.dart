import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_error.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/locale.dart';

class PlaybackSettingsDialog extends StatefulWidget {
  const PlaybackSettingsDialog({
    super.key,
    required this.intro,
    required this.outro,
    required this.volume,
    required this.onVolumeChanged,
    required this.onSave,
  });

  final int intro;
  final int outro;
  final double volume;
  final ValueChanged<double> onVolumeChanged;
  final Future<void> Function(int intro, int outro) onSave;

  @override
  State<PlaybackSettingsDialog> createState() => _PlaybackSettingsDialogState();
}

class _PlaybackSettingsDialogState extends State<PlaybackSettingsDialog> {
  final _form = GlobalKey<FormState>();
  late final _intro = TextEditingController(text: widget.intro.toString());
  late final _outro = TextEditingController(text: widget.outro.toString());
  late double _volume = widget.volume;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _intro.dispose();
    _outro.dispose();
    super.dispose();
  }

  void _hideKeyboard() => FocusScope.of(context).unfocus();

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    _hideKeyboard();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
          int.tryParse(_intro.text) ?? 0, int.tryParse(_outro.text) ?? 0);
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = context.localeText('保存失败：${ApiError.messageFor(failure)}',
            'Save failed: ${ApiError.messageFor(failure)}');
      });
    }
  }

  Widget _field(TextEditingController controller, String label,
      {required bool last}) {
    return TextFormField(
      key: ValueKey(last ? 'skip_outro' : 'skip_intro'),
      controller: controller,
      enabled: !_saving,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      onFieldSubmitted: (_) {
        if (last) {
          _hideKeyboard();
        } else {
          FocusScope.of(context).nextFocus();
        }
      },
      onTapOutside: (_) => _hideKeyboard(),
      validator: (value) => value != null &&
              value.isNotEmpty &&
              int.tryParse(value) == null
          ? context.localeText('请输入有效的秒数', 'Enter a valid number of seconds')
          : null,
      decoration: InputDecoration(
        labelText: label,
        helperText: context.localeText('0 表示不跳过', '0 disables skipping'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: context.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 384),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _hideKeyboard,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.localeText('播放设置', 'Playback Settings'),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      onPressed: _hideKeyboard,
                      tooltip: context.localeText('收起键盘', 'Hide keyboard'),
                      icon: const Icon(Icons.keyboard_hide_rounded),
                    ),
                    IconButton(
                      onPressed:
                          _saving ? null : () => Navigator.pop(context, false),
                      tooltip: context.l10n.commonClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            context.localeText('仅对本机的这本书生效，离线也可设置。',
                                'Saved for this book on this device. Works offline.'),
                            style: TextStyle(
                                color: context.mutedText, fontSize: 12),
                          ),
                          const SizedBox(height: 20),
                          _field(
                              _intro,
                              context.localeText(
                                  '跳过片头 (秒)', 'Skip Intro (sec)'),
                              last: false),
                          const SizedBox(height: 20),
                          _field(
                              _outro,
                              context.localeText(
                                  '跳过片尾 (秒)', 'Skip Outro (sec)'),
                              last: true),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                  child:
                                      Text(context.localeText('音量', 'Volume'))),
                              Text('${(_volume * 100).round()}%'),
                            ],
                          ),
                          Slider(
                            value: _volume.clamp(0, 1).toDouble(),
                            onChanged: _saving
                                ? null
                                : (value) {
                                    setState(() => _volume = value);
                                    widget.onVolumeChanged(value);
                                  },
                          ),
                          if (_error != null)
                            Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context, false),
                        child: Text(context.l10n.commonCancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.check_rounded, size: 20),
                        label: Text(context.localeText('保存', 'Save')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

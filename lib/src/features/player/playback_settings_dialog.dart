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
    this.rewindSeconds = 10,
    this.onRewindChanged,
    this.bookSpeed,
    this.onDefaultSpeed,
  });

  final int intro;
  final int outro;
  final double volume;
  final ValueChanged<double> onVolumeChanged;
  final Future<void> Function(int intro, int outro) onSave;
  final int rewindSeconds;
  final ValueChanged<int>? onRewindChanged;
  final double? bookSpeed;
  final Future<void> Function()? onDefaultSpeed;

  @override
  State<PlaybackSettingsDialog> createState() => _PlaybackSettingsDialogState();
}

class _PlaybackSettingsDialogState extends State<PlaybackSettingsDialog> {
  final _form = GlobalKey<FormState>();
  late final _intro = TextEditingController(text: widget.intro.toString());
  late final _outro = TextEditingController(text: widget.outro.toString());
  late double _volume = widget.volume;
  late int _rewindSeconds = widget.rewindSeconds;
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
                          if (widget.onDefaultSpeed != null) ...[
                            Text(context.localeText(
                                '本书倍速：${widget.bookSpeed?.toStringAsFixed(1)}×',
                                'Book speed: ${widget.bookSpeed?.toStringAsFixed(1)}×')),
                            Text(
                                context.localeText('播放器调整的倍速会按书籍记住。',
                                    'Speed changes in the player are remembered per book.'),
                                style: TextStyle(
                                    fontSize: 12, color: context.mutedText)),
                            Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                    onPressed: _saving
                                        ? null
                                        : () async {
                                            await widget.onDefaultSpeed!();
                                            if (context.mounted) {
                                              Navigator.pop(context, true);
                                            }
                                          },
                                    child: Text(context.localeText(
                                        '恢复默认倍速', 'Use default speed')))),
                            const SizedBox(height: 12),
                          ],
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
                          if (widget.onRewindChanged != null) ...[
                            DropdownButtonFormField<int>(
                              initialValue: _rewindSeconds,
                              decoration: InputDecoration(
                                  labelText: context.localeText('智能回退（全部书籍）',
                                      'Smart rewind (all books)')),
                              items: ({0, 5, 10, 15, 30, _rewindSeconds}
                                      .toList()
                                    ..sort())
                                  .map((value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(value == 0
                                          ? context.localeText('关闭', 'Off')
                                          : context.localeText(
                                              '$value 秒', '$value seconds'))))
                                  .toList(),
                              onChanged: _saving
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        setState(() => _rewindSeconds = value);
                                        widget.onRewindChanged!(value);
                                      }
                                    },
                            ),
                            Padding(
                                padding:
                                    const EdgeInsets.only(top: 8, bottom: 16),
                                child: Text(
                                    context.localeText('暂停满一分钟后续播时回退；手动跳转不回退。',
                                        'Rewind after pausing for a minute. Manual navigation keeps your chosen position.'),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: context.mutedText))),
                          ],
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

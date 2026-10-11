import 'package:flutter/material.dart';

import '../theme/kp_colors.dart';
import '../theme/kp_text.dart';
import '../theme/kp_theme.dart';

/// Flat graphite panel with a hairline border.
class KpPanel extends StatelessWidget {
  const KpPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(KpSpace.m),
    this.color = KpColors.surface,
    this.radius = KpRadius.m,
    this.borderColor = KpColors.stroke,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Small rectangular tag for technical values ("4K", "30 fps", "HEVC").
class KpTag extends StatelessWidget {
  const KpTag(this.text, {super.key, this.color = KpColors.textDim, this.filled = false});

  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.16) : KpColors.surface3,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text, style: KpText.metricSmall.copyWith(color: filled ? color : KpColors.textDim)),
    );
  }
}

/// Green "LIVE" block. When [active] is false it renders a grey "NO SIGNAL".
class KpLiveBadge extends StatelessWidget {
  const KpLiveBadge({super.key, required this.active, this.label});

  final bool active;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = active ? KpColors.live : KpColors.inactive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: active ? 0.18 : 0.25),
        border: Border.all(color: c),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label ?? (active ? 'LIVE' : 'НЕТ СИГНАЛА'),
        style: KpText.label.copyWith(color: active ? KpColors.live : KpColors.textDim, fontSize: 11),
      ),
    );
  }
}

/// Status dot with optional pulse (used for "searching", "connecting").
class KpStatusDot extends StatefulWidget {
  const KpStatusDot({super.key, required this.color, this.pulse = false, this.size = 8});

  final Color color;
  final bool pulse;
  final double size;

  @override
  State<KpStatusDot> createState() => _KpStatusDotState();
}

class _KpStatusDotState extends State<KpStatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant KpStatusDot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.pulse && _c.isAnimating) {
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = widget.pulse ? 0.35 + 0.65 * _c.value : 1.0;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: t),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: widget.color.withValues(alpha: 0.45 * t), blurRadius: 6),
            ],
          ),
        );
      },
    );
  }
}

/// Four-bar quality indicator. [level] 0..4, null = unknown (all dim).
class KpSignalBars extends StatelessWidget {
  const KpSignalBars({super.key, required this.level, this.height = 12});

  final int? level;
  final double height;

  @override
  Widget build(BuildContext context) {
    final lv = level ?? 0;
    final color = level == null
        ? KpColors.inactive
        : lv >= 3
            ? KpColors.live
            : lv == 2
                ? KpColors.warn
                : KpColors.rec;
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (i) {
          return Container(
            margin: const EdgeInsets.only(left: 1.5),
            width: 3,
            height: height * (0.4 + 0.2 * i),
            decoration: BoxDecoration(
              color: i < lv ? color : KpColors.inactive.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(1),
            ),
          );
        }),
      ),
    );
  }
}

/// Vertical tool button for monitor rails: icon over a short label.
class KpToolButton extends StatelessWidget {
  const KpToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
    this.compact = false,
    this.width,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final bool enabled;
  final bool compact;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final fg = !enabled
        ? KpColors.textMute
        : selected
            ? KpColors.text
            : KpColors.textDim;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(KpRadius.s),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: width ?? (compact ? 48 : 56),
          padding: EdgeInsets.symmetric(vertical: compact ? 6 : 8),
          decoration: BoxDecoration(
            color: selected ? KpColors.surface3 : Colors.transparent,
            borderRadius: BorderRadius.circular(KpRadius.s),
            border: Border.all(color: selected ? KpColors.select : Colors.transparent),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 18 : 20, color: fg),
              if (!compact) ...[
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: KpText.caption.copyWith(fontSize: 10, color: fg),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Round icon button on top of video (dark glass, no blur to keep GPU free).
class KpRoundButton extends StatelessWidget {
  const KpRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 44,
    this.tooltip,
    this.active = false,
    this.activeColor = KpColors.text,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final String? tooltip;
  final bool active;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: active ? activeColor.withValues(alpha: 0.2) : const Color(0x99000000),
      shape: CircleBorder(side: BorderSide(color: active ? activeColor : KpColors.strokeStrong)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.45, color: onTap == null ? KpColors.textMute : (active ? activeColor : KpColors.text)),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Segmented control: compact pill group with one selected value.
class KpSegmented<T> extends StatelessWidget {
  const KpSegmented({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.expand = true,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T>? onChanged;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final children = values.map((v) {
      final sel = v == selected;
      final child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(v),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? KpColors.surface3 : Colors.transparent,
            borderRadius: BorderRadius.circular(KpRadius.s - 1),
            border: Border.all(color: sel ? KpColors.strokeStrong : Colors.transparent),
          ),
          child: Text(
            labelOf(v),
            maxLines: 1,
            style: KpText.caption.copyWith(
              color: sel ? KpColors.text : KpColors.textDim,
              fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      );
      return expand ? Expanded(child: child) : child;
    }).toList();
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: KpColors.surface2,
        borderRadius: BorderRadius.circular(KpRadius.s + 2),
        border: Border.all(color: KpColors.stroke),
      ),
      child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, children: children),
    );
  }
}

/// Settings section: small caption above a grouped panel.
class KpSection extends StatelessWidget {
  const KpSection({super.key, this.title, required this.children, this.footer});

  final String? title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) items.add(const Divider(height: 1, indent: KpSpace.m));
      items.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: KpSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(KpSpace.xs, 0, KpSpace.xs, KpSpace.s),
              child: Text(title!, style: KpText.heading.copyWith(fontSize: 14)),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(KpRadius.m),
            child: KpPanel(
              padding: EdgeInsets.zero,
              color: KpColors.surface2,
              child: Column(children: items),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(KpSpace.xs, KpSpace.s, KpSpace.xs, 0),
              child: Text(footer!, style: KpText.caption),
            ),
        ],
      ),
    );
  }
}

/// Settings row: label on the left, value + chevron on the right.
class KpRow extends StatelessWidget {
  const KpRow({
    super.key,
    required this.label,
    this.value,
    this.onTap,
    this.trailing,
    this.subtitle,
    this.valueColor,
    this.leading,
  });

  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String? subtitle;
  final Color? valueColor;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KpSpace.m, vertical: KpSpace.s),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: KpSpace.m)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: KpText.body),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: KpText.caption),
                    ],
                  ],
                ),
              ),
              if (value != null)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: KpSpace.s),
                    child: Text(
                      value!,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: KpText.metric.copyWith(
                        color: valueColor ?? KpColors.textDim,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              if (trailing != null) ...[const SizedBox(width: KpSpace.s), trailing!],
              if (onTap != null && trailing == null)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.chevron_right, size: 18, color: KpColors.textMute),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class KpSwitchRow extends StatelessWidget {
  const KpSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return KpRow(
      label: label,
      subtitle: subtitle,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}

/// Primary rectangular button (launch / dialogs).
class KpButton extends StatelessWidget {
  const KpButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = KpColors.surface3,
    this.foreground = KpColors.text,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final Color foreground;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 18, color: foreground), const SizedBox(width: 8)],
        Flexible(
          child: Text(label,
              textAlign: TextAlign.center,
              style: KpText.label.copyWith(color: foreground, letterSpacing: 0.3)),
        ),
      ],
    );
    return Material(
      color: onPressed == null ? KpColors.surface2 : color,
      borderRadius: BorderRadius.circular(KpRadius.m),
      child: InkWell(
        borderRadius: BorderRadius.circular(KpRadius.m),
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: KpSpace.l, vertical: KpSpace.m),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KpRadius.m),
            border: Border.all(color: KpColors.strokeStrong),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Empty / info state placeholder.
class KpEmptyState extends StatelessWidget {
  const KpEmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KpSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: KpColors.textMute),
            const SizedBox(height: KpSpace.m),
            Text(title, style: KpText.heading, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: KpSpace.s),
              Text(message!, style: KpText.bodyDim, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: KpSpace.l), action!],
          ],
        ),
      ),
    );
  }
}

/// Inline warning banner (amber / red).
class KpBanner extends StatelessWidget {
  const KpBanner({super.key, required this.text, this.color = KpColors.warn, this.icon = Icons.warning_amber_rounded});

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: KpSpace.m, vertical: KpSpace.s),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(KpRadius.s),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Flexible(child: Text(text, style: KpText.caption.copyWith(color: KpColors.text))),
        ],
      ),
    );
  }
}

void showKpToast(BuildContext context, String message, {Color? color}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    duration: const Duration(seconds: 3),
    content: Row(
      children: [
        if (color != null) ...[KpStatusDot(color: color), const SizedBox(width: 10)],
        Expanded(child: Text(message, style: KpText.body)),
      ],
    ),
  ));
}

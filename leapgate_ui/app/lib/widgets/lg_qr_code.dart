// The QR code of the "turn on 2FA" dialog and the line with the secret under it
// (02 §1.6.3, A-P6-设置-对话框.html ".qr", ".kv"). The code is drawn by
// `qr_flutter` (the version upstream pins).

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';

/// A QR code on a small white card (`.qr`).
///
/// A scanner wants dark modules on a light ground, so the card keeps the light
/// theme's ink on its white in both themes: the code is not in the page's colours
/// in the dark theme, on purpose. The quiet zone is the 8 px of padding plus
/// the code's own.
class LgQrCode extends StatelessWidget {
  const LgQrCode({
    super.key,
    required this.data,
    required this.semanticLabel,
    this.size = 168,
  });

  /// What the code holds (the `otpauth://` link).
  final String data;

  /// What a screen reader says for the picture ("二维码"). The code itself is
  /// read by a phone, not by the reader, and the secret under it is the way
  /// for those who cannot scan: see [LgQrKeyRow].
  final String semanticLabel;

  /// The edge of the card, padding included.
  final double size;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF14282B);
    final paper = LgColors.light.surface;
    return Semantics(
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(LgSpace.s2),
          decoration: BoxDecoration(
            color: paper,
            borderRadius: BorderRadius.circular(LgRadius.r12),
          ),
          child: QrImageView(
            data: data,
            padding: EdgeInsets.zero,
            backgroundColor: paper,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
            eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: ink),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// The secret under the code (`.kv`): a bold label, the secret in the monospace
/// face (the caller breaks it into groups and lines), and a copy button. It is
/// how to turn 2FA on without a camera.
class LgQrKeyRow extends StatelessWidget {
  const LgQrKeyRow({
    super.key,
    required this.label,
    required this.value,
    required this.copyLabel,
    required this.onCopy,
    this.copySemanticLabel,
  });

  /// "密钥".
  final String label;

  /// "ABCD EFGH IJKL MNOP\nQRST UVWX YZ23 4567".
  final String value;

  /// "复制".
  final String copyLabel;
  final VoidCallback? onCopy;

  /// "复制密钥".
  final String? copySemanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: t.sizes.button),
      child: Row(
        children: [
          Text(
            label,
            style: t.textM.copyWith(color: c.text, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: LgSpace.s3),
          Expanded(
            child: Text(
              value,
              style: LgTokens.monoStyle(
                t.sizes.fsS,
                t.sizes.lhS,
              ).copyWith(color: c.text, letterSpacing: .02 * t.sizes.fsS),
            ),
          ),
          const SizedBox(width: LgSpace.s3),
          LgButton(
            label: copyLabel,
            icon: LgIcons.copy,
            kind: LgButtonKind.text,
            semanticLabel: copySemanticLabel,
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}

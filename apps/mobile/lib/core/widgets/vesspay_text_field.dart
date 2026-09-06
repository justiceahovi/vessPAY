import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Styled text field strictly complying with DESIGN.md form input specifications
class VessPayTextField extends StatefulWidget {
  final String label;
  final String? hintText;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final TextInputType keyboardType;
  final bool isPassword;
  final bool enabled;
  final Key? fieldKey;
  final Widget? prefixIcon;
  final void Function(String)? onChanged;

  const VessPayTextField({
    super.key,
    required this.label,
    this.hintText,
    this.controller,
    this.validator,
    this.keyboardType = TextInputType.text,
    this.isPassword = false,
    this.enabled = true,
    this.fieldKey,
    this.prefixIcon,
    this.onChanged,
  });

  @override
  State<VessPayTextField> createState() => _VessPayTextFieldState();
}

class _VessPayTextFieldState extends State<VessPayTextField> {
  bool _obscureText = true;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.isPassword;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Input Label
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.bodyStrong,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 6),
        // TextFormField
        TextFormField(
          key: widget.fieldKey,
          controller: widget.controller,
          validator: widget.validator,
          keyboardType: widget.keyboardType,
          obscureText: widget.isPassword ? _obscureText : false,
          enabled: widget.enabled,
          onChanged: widget.onChanged,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: AppColors.ink,
          ),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColors.mutedSoft,
            ),
            filled: true,
            fillColor: AppColors.canvas,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            prefixIcon: widget.prefixIcon,
            suffixIcon: widget.isPassword
                ? IconButton(
                    icon: Icon(
                      _obscureText
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: AppColors.muted,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureText = !_obscureText;
                      });
                    },
                  )
                : null,
            // Border definitions per DESIGN.md
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.hairline, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.hairline, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.error, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.error, width: 1.5),
            ),
            errorStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.error,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

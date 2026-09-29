import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_elevation.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../../core/widgets/sugo_button.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_pill.dart';
import '../../onboarding/models/client_onboarding_models.dart';
import '../../onboarding/services/client_registration_service.dart';
import '../../onboarding/widgets/location_pin_step.dart';
import '../../rb_cars/services/rb_cars_service.dart';

/// Adds or edits one saved address.
///
/// Reuses [LocationPinStep] - the same map, search box and "use my location"
/// button the registration flow and the booking flow use. Three pickers that
/// behaved differently would be three chances to get a technician sent to the
/// wrong street.
///
/// ## Why the label is chips plus a free text field
///
/// Nearly every address is "Home" or "Work", so those are one tap. But a
/// Philippine client just as often needs "Mum's place" or "Lola's store", and
/// a fixed enum would have forced those into "Other" - which tells the
/// technician nothing. The chips are shortcuts into a free text field, not a
/// replacement for it.
class AddressEditorScreen extends StatefulWidget {
  const AddressEditorScreen({
    super.key,
    this.address,
    this.service,
    this.forceDefault = false,
  });

  /// The address being edited, or null to add a new one.
  final SavedAddress? address;

  /// Tests only.
  final ClientRegistrationService? service;

  /// True for a client's very first address: there is nothing else for it to
  /// defer to, so the default switch is on and locked.
  final bool forceDefault;

  @override
  State<AddressEditorScreen> createState() => _AddressEditorScreenState();
}

class _AddressEditorScreenState extends State<AddressEditorScreen> {
  late final ClientRegistrationService _service =
      widget.service ?? ClientRegistrationService();

  late final TextEditingController _label = TextEditingController(
    text: widget.address?.label ?? 'Home',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.address?.notes ?? '',
  );

  GeoPlace? _place;
  late bool _isDefault =
      widget.forceDefault || (widget.address?.isDefault ?? false);
  bool _saving = false;

  static const List<String> _suggestions = <String>[
    'Home',
    'Work',
    'Office',
    'Parents',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    final SavedAddress? existing = widget.address;
    if (existing != null) _place = existing.place;
  }

  @override
  void dispose() {
    _label.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _canSave => _place != null && _label.text.trim().isNotEmpty;

  Future<void> _save() async {
    final GeoPlace? place = _place;
    if (place == null || _saving) return;

    setState(() => _saving = true);
    try {
      await _service.saveAddress(
        SavedAddress(
          id: widget.address?.id,
          label: _label.text.trim(),
          latitude: place.latitude,
          longitude: place.longitude,
          addressText: place.addressText,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          isDefault: _isDefault,
        ),
      );
      if (!mounted) return;
      UiFeedback.showSuccess(
        context,
        widget.address == null ? 'Address saved.' : 'Address updated.',
      );
      Navigator.of(context).pop(true);
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      UiFeedback.showError(context, failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: SugoAppBar(
        title: widget.address == null ? 'Add address' : 'Edit address',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.screenPadding,
          AppSizes.md,
          AppSizes.screenPadding,
          AppSizes.xxl,
        ),
        children: <Widget>[
          SugoCard(
            padding: const EdgeInsets.all(AppSizes.md),
            child: LocationPinStep(
              place: _place,
              onPlaceChanged: (GeoPlace place) =>
                  setState(() => _place = place),
              title: 'Where is it?',
              subtitle:
                  'Drag the pin, search the address, or use your current '
                  'location.',
              mapHeight: 240,
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          Text('Label', style: AppTextStyles.label),
          const SizedBox(height: AppSizes.sm),
          Wrap(
            spacing: AppSizes.sm,
            runSpacing: AppSizes.sm,
            children: <Widget>[
              for (final String suggestion in _suggestions)
                SugoPill(
                  label: suggestion,
                  selected:
                      _label.text.trim().toLowerCase() ==
                      suggestion.toLowerCase(),
                  onTap: () => setState(() {
                    _label.text = suggestion;
                    _label.selection = TextSelection.collapsed(
                      offset: suggestion.length,
                    );
                  }),
                ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          AppTextField(
            label: 'Name this address',
            hint: 'Home, Office, Lola\'s house…',
            controller: _label,
            icon: Icons.label_outline_rounded,
            textCapitalization: TextCapitalization.words,
            showValidTick: false,
            onSubmitted: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSizes.lg),
          AppTextField(
            label: 'Landmarks (optional)',
            hint: 'Green gate, ask for Ate Beth, 2nd floor…',
            controller: _notes,
            icon: Icons.sticky_note_2_outlined,
            maxLines: 3,
            showValidTick: false,
            helper: 'Anything a map cannot tell your technician.',
          ),
          const SizedBox(height: AppSizes.lg),
          SugoCard(
            elevation: SugoElevation.sm,
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppSizes.radius),
                  ),
                  child: const Icon(
                    Icons.star_rounded,
                    size: 19,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Use as default', style: AppTextStyles.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        widget.forceDefault
                            ? 'Your first address is always the default.'
                            : 'Chosen automatically when you book a repair.',
                        style: AppTextStyles.micro,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _isDefault,
                  onChanged: widget.forceDefault
                      ? null
                      : (bool value) => setState(() => _isDefault = value),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          boxShadow: AppElevation.navBar,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.screenPadding,
              AppSizes.md,
              AppSizes.screenPadding,
              AppSizes.md,
            ),
            child: SugoButton(
              label: widget.address == null ? 'Save address' : 'Save changes',
              isLoading: _saving,
              onPressed: _canSave ? _save : null,
            ),
          ),
        ),
      ),
    );
  }
}

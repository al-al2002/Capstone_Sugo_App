import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../../core/widgets/sugo_button.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_dialog.dart';
import '../../../core/widgets/sugo_empty_state.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../../core/widgets/sugo_status_badge.dart';
import '../../onboarding/models/client_onboarding_models.dart';
import '../../onboarding/services/client_registration_service.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import 'address_editor_screen.dart';

/// The client's saved addresses: Home, Work, anywhere else they get repairs.
///
/// ## Why this screen did not exist before
///
/// The table has always supported many addresses - `client_saved_addresses`
/// was built one-to-many deliberately - but registration only ever wrote one,
/// and nothing in the app could add a second. So a client who moved, or who
/// wanted a repair at the office, had to re-pin the map inside the booking
/// flow every time.
///
/// Nothing on the server changed to build this. The policy already grants all
/// four verbs on a client's own rows, and the single-default rule is enforced
/// by a trigger rather than by whichever screen happens to be writing.
class SavedAddressesScreen extends StatefulWidget {
  const SavedAddressesScreen({super.key, this.service});

  /// Tests only.
  final ClientRegistrationService? service;

  @override
  State<SavedAddressesScreen> createState() => _SavedAddressesScreenState();
}

class _SavedAddressesScreenState extends State<SavedAddressesScreen> {
  late final ClientRegistrationService _service =
      widget.service ?? ClientRegistrationService();

  List<SavedAddress> _addresses = const <SavedAddress>[];
  bool _loading = true;
  String? _error;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<SavedAddress> rows = await _service.loadAddresses();
      if (!mounted) return;
      setState(() {
        _addresses = rows;
        _loading = false;
        _error = null;
      });
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _edit([SavedAddress? address]) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AddressEditorScreen(
          address: address,
          service: widget.service,
          // The first address a client saves has to be their default; there
          // is nothing else for it to defer to.
          forceDefault: _addresses.isEmpty,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _setDefault(SavedAddress address) async {
    if (address.id == null) return;
    setState(() => _busyId = address.id);
    try {
      await _service.setDefaultAddress(address.id!);
      await _load();
      if (mounted) {
        UiFeedback.showSuccess(context, '${address.label} is now your default.');
      }
    } on RbCarsFailure catch (failure) {
      if (mounted) UiFeedback.showError(context, failure.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(SavedAddress address) async {
    if (address.id == null) return;

    final bool confirmed = await showSugoConfirmDialog(
      context: context,
      icon: Icons.delete_outline_rounded,
      title: 'Delete ${address.label}?',
      message:
          'Bookings you have already made keep the address they were made '
          'with. Only this saved shortcut is removed.',
      confirmLabel: 'Delete',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = address.id);
    try {
      await _service.deleteAddress(address.id!);
      await _load();
      if (mounted) UiFeedback.showSuccess(context, 'Address deleted.');
    } on RbCarsFailure catch (failure) {
      if (mounted) UiFeedback.showError(context, failure.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const SugoAppBar(title: 'Saved addresses'),
      body: _body(),
      bottomNavigationBar: _addresses.isEmpty && !_loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.screenPadding,
                  AppSizes.sm,
                  AppSizes.screenPadding,
                  AppSizes.md,
                ),
                child: SugoButton(
                  label: 'Add an address',
                  icon: Icons.add_location_alt_rounded,
                  onPressed: () => _edit(),
                ),
              ),
            ),
    );
  }

  Widget _body() {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        children: const <Widget>[SugoSkeletonList(count: 2, showAvatar: false)],
      );
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        children: <Widget>[
          SugoEmptyState.error(
            title: 'Addresses did not load',
            message: '$_error Check your connection, then try again.',
            onAction: () {
              setState(() => _loading = true);
              _load();
            },
          ),
        ],
      );
    }

    if (_addresses.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        children: <Widget>[
          SugoEmptyState(
            icon: Icons.location_off_outlined,
            title: 'No saved addresses',
            message:
                'Save the places you usually need repairs - your home, your '
                'office - and booking becomes two taps instead of a map pin.',
            actionLabel: 'Add an address',
            onAction: () => _edit(),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.screenPadding,
          AppSizes.md,
          AppSizes.screenPadding,
          AppSizes.xxl,
        ),
        itemCount: _addresses.length,
        itemBuilder: (BuildContext context, int index) {
          final SavedAddress address = _addresses[index];
          return _AddressCard(
            address: address,
            busy: _busyId == address.id,
            onEdit: () => _edit(address),
            onDelete: () => _delete(address),
            onSetDefault: address.isDefault ? null : () => _setDefault(address),
          );
        },
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
  });

  final SavedAddress address;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onSetDefault;

  /// A recognisable glyph per label, falling back to a generic pin. Matching
  /// on the words people actually type is enough here - the label is free
  /// text, and an unknown one simply gets the pin.
  IconData get _icon {
    final String label = address.label.toLowerCase();
    if (label.contains('home') || label.contains('bahay')) {
      return Icons.home_rounded;
    }
    if (label.contains('work') ||
        label.contains('office') ||
        label.contains('shop')) {
      return Icons.work_rounded;
    }
    return Icons.place_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      onTap: busy ? null : onEdit,
      child: Opacity(
        opacity: busy ? 0.5 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: AppSizes.iconTile,
                  height: AppSizes.iconTile,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppSizes.radius),
                  ),
                  child: Icon(_icon, size: 21, color: AppColors.primary),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              address.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.titleSmall,
                            ),
                          ),
                          if (address.isDefault) ...<Widget>[
                            const SizedBox(width: AppSizes.sm),
                            const SugoStatusBadge(
                              label: 'Default',
                              icon: Icons.star_rounded,
                              tone: SugoTone.brand,
                              dense: true,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        address.addressText,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption,
                      ),
                      if ((address.notes ?? '').trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSizes.sm),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Icon(
                              Icons.sticky_note_2_outlined,
                              size: 14,
                              color: AppColors.hint,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                address.notes!.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.micro,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            const Divider(height: 1),
            const SizedBox(height: AppSizes.sm),
            Row(
              children: <Widget>[
                TextButton.icon(
                  onPressed: busy ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                ),
                if (onSetDefault != null)
                  TextButton.icon(
                    onPressed: busy ? null : onSetDefault,
                    icon: const Icon(Icons.star_outline_rounded, size: 16),
                    label: const Text('Set default'),
                  ),
                const Spacer(),
                TextButton.icon(
                  onPressed: busy ? null : onDelete,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/session/session_state.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../../rb_cars/widgets/location_picker_map.dart';
import '../services/profile_setup_service.dart';

/// Profile photo and - for technicians - the workshop.
///
/// ## Two ways in
///
/// * [ProfileSetupScreen.firstRun] - shown by `AuthGate` the first time a newly
///   approved account signs in. Saving OR skipping stamps
///   `profile_setup_completed_at`, so it is asked exactly once.
/// * [ProfileSetupScreen.edit] - pushed from the Profile tab, for anyone who
///   skipped or wants to change something later. It never touches the stamp.
///
/// The edit route is what makes "Skip for now" honest. Without it, skipping
/// would mean the workshop could never be set, and "for now" would be a lie.
///
/// ## What it does not offer
///
/// The name. `full_name` is what the ID review checked against the document,
/// so it is shown read-only with the reason. Letting an approved account rename
/// itself here would undo the verification it just passed.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen.firstRun({super.key}) : isFirstRun = true;

  const ProfileSetupScreen.edit({super.key}) : isFirstRun = false;

  final bool isFirstRun;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final ProfileSetupService _service = ProfileSetupService();
  final TextEditingController _shopName = TextEditingController();

  XFile? _photo;
  double? _shopLat;
  double? _shopLng;

  bool _loadingWorkshop = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadWorkshop();
  }

  @override
  void dispose() {
    _shopName.dispose();
    super.dispose();
  }

  SessionProfile? get _profile => context.read<SessionController>().profile;

  bool get _isTechnician => _profile?.isTechnician ?? false;

  Future<void> _loadWorkshop() async {
    if (!_isTechnician) {
      setState(() => _loadingWorkshop = false);
      return;
    }
    final workshop = await _service.workshop();
    if (!mounted) return;
    setState(() {
      _shopName.text = workshop?.name ?? '';
      _shopLat = workshop?.latitude;
      _shopLng = workshop?.longitude;
      _loadingWorkshop = false;
    });
  }

  Future<void> _pickPhoto() async {
    try {
      final XFile? picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // An avatar is shown at most ~70 px wide. 800 px keeps it sharp on a
        // dense screen while staying far under the bucket's 2 MB limit.
        maxWidth: 800,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      setState(() => _photo = picked);
    } catch (_) {
      if (!mounted) return;
      UiFeedback.showError(context, 'Could not open your photos.');
    }
  }

  Future<void> _finish({required bool skip}) async {
    if (_saving) return;
    setState(() => _saving = true);

    final SessionController session = context.read<SessionController>();

    try {
      String? avatarUrl;
      if (!skip && _photo != null) {
        avatarUrl = await _service.uploadAvatar(_photo!);
      }

      await _service.save(
        avatarUrl: avatarUrl,
        shopName: skip || !_isTechnician ? null : _shopName.text,
        shopLatitude: skip ? null : _shopLat,
        shopLongitude: skip ? null : _shopLng,
        isTechnician: _isTechnician,
        markComplete: widget.isFirstRun,
      );

      if (!mounted) return;

      if (widget.isFirstRun) {
        // Shown BEFORE the refresh, not after. The refresh is what makes
        // AuthGate replace this screen with the dashboard, so by the time it
        // returns this widget is unmounted and could not show anything. The
        // messenger belongs to the MaterialApp, so a message queued now
        // survives the swap and appears over the dashboard.
        UiFeedback.showSuccess(
          context,
          skip
              ? 'You can finish your profile any time from the Profile tab.'
              : 'Your profile is set up.',
        );
        // The stamp is now set, so the destination changes and the gate moves
        // on by itself.
        await session.refresh();
        return;
      }

      await session.refresh();
      if (!mounted) return;
      UiFeedback.showSuccess(context, 'Profile updated.');
      Navigator.of(context).pop();
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      UiFeedback.showError(context, failure.message);
    } catch (_) {
      if (!mounted) return;
      UiFeedback.showError(context, 'Could not save your profile.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final SessionProfile? profile = context.watch<SessionController>().profile;
    final String firstName = profile?.displayName ?? 'there';

    return PopScope(
      // The first run is a gate, not a page on a stack: there is nothing behind
      // it to go back to. Skip is the way past it.
      canPop: !widget.isFirstRun,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: SugoAppBar(
          surface: true,
          automaticallyImplyLeading: !widget.isFirstRun,
          title: widget.isFirstRun ? 'Set up your profile' : 'Edit profile',
          actions: <Widget>[
            if (widget.isFirstRun)
              TextButton(
                onPressed: _saving ? null : () => _finish(skip: true),
                child: const Text('Skip for now'),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.screenPadding,
            AppSizes.lg,
            AppSizes.screenPadding,
            AppSizes.xxl,
          ),
          children: <Widget>[
            if (widget.isFirstRun) ...<Widget>[
              Text(
                'Welcome, $firstName - you\'re approved!',
                style: AppTextStyles.headline,
              ),
              const SizedBox(height: 4),
              Text(
                _isTechnician
                    ? 'Two quick things before your first job: a photo so '
                          'clients recognise you, and your workshop so anyone '
                          'collecting a repair can find it.'
                    : 'Add a photo so the technicians you book can recognise '
                          'you when they arrive.',
                style: AppTextStyles.caption.copyWith(
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSizes.xl),
            ],

            _AvatarPicker(
              photo: _photo,
              currentUrl: profile?.avatarUrl,
              initials: profile?.initials ?? '?',
              onPick: _saving ? null : _pickPhoto,
            ),
            const SizedBox(height: AppSizes.md),
            Center(
              child: Text(
                profile?.fullName?.trim().isNotEmpty ?? false
                    ? profile!.fullName!
                    : 'SUGO user',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Center(
              child: Text(
                'Your name matches your verified ID, so it cannot be changed here.',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption.copyWith(fontSize: 12),
              ),
            ),

            if (_isTechnician) ...<Widget>[
              const SizedBox(height: AppSizes.xl),
              const Text(
                'Your workshop',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Where you repair units that cannot be fixed on site. Clients '
                'who collect a repaired appliance are routed here, and it is '
                'only shared with clients who have booked you.',
                style: AppTextStyles.caption.copyWith(fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: AppSizes.md),
              TextField(
                controller: _shopName,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Workshop name',
                  hintText: 'e.g. JM Electronics Repair',
                ),
              ),
              const SizedBox(height: AppSizes.md),
              if (_loadingWorkshop)
                // The map's own footprint while the saved workshop loads,
                // so the form below does not jump when it arrives.
                const SugoSkeleton(height: 240, radius: AppSizes.radius)
              else
                LocationPickerMap(
                  latitude: _shopLat,
                  longitude: _shopLng,
                  onChanged: (double lat, double lng, String? _) =>
                      setState(() {
                        _shopLat = lat;
                        _shopLng = lng;
                      }),
                ),
            ],

            const SizedBox(height: AppSizes.xl),
            SizedBox(
              height: AppSizes.buttonHeight,
              child: FilledButton(
                onPressed: _saving ? null : () => _finish(skip: false),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(widget.isFirstRun ? 'Save and continue' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A round photo with a camera badge. Shows, in order of preference: the photo
/// just picked, the one already saved, or the initials.
class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({
    required this.photo,
    required this.currentUrl,
    required this.initials,
    required this.onPick,
  });

  final XFile? photo;
  final String? currentUrl;
  final String initials;
  final VoidCallback? onPick;

  static const double _size = 104;

  @override
  Widget build(BuildContext context) {
    final Widget image;
    if (photo != null) {
      // Bytes, not `Image.file`: Flutter Web has no filesystem, and this keeps
      // the preview working everywhere the picker does.
      image = FutureBuilder<Uint8List>(
        future: photo!.readAsBytes(),
        builder: (BuildContext context, AsyncSnapshot<Uint8List> snap) =>
            snap.hasData
            ? Image.memory(
                snap.data!,
                fit: BoxFit.cover,
                width: _size,
                height: _size,
              )
            : _initials(),
      );
    } else if (currentUrl != null && currentUrl!.isNotEmpty) {
      image = Image.network(
        currentUrl!,
        fit: BoxFit.cover,
        width: _size,
        height: _size,
        errorBuilder: (_, __, ___) => _initials(),
      );
    } else {
      image = _initials();
    }

    return Center(
      child: GestureDetector(
        onTap: onPick,
        child: Stack(
          children: <Widget>[
            ClipOval(
              child: SizedBox(width: _size, height: _size, child: image),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _initials() {
    return Container(
      color: AppColors.primarySoft,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../models/basic_problem.dart';
import '../models/job_enums.dart';
import '../providers/job_posting_provider.dart';
import '../widgets/basic_problem_card.dart';
import '../widgets/device_brand_picker.dart';
import '../widgets/posting_field.dart';
import '../widgets/posting_scaffold.dart';
import 'where_and_when_screen.dart';

/// Step 4 of 6: which exact machine, and what happened to it?
///
/// Everything on this screen is optional, and the CTA is never disabled. The
/// fields here sharpen the match - brand and device feed the Stage 1 ladder,
/// the description is what a technician actually reads before accepting - but
/// a client who cannot find a model number must still be able to post. Stage 1
/// already degrades to device-category matching when the brand is null, so the
/// cost of skipping this step is a slightly weaker ranking, not a failure.
class DeviceDetailsScreen extends StatefulWidget {
  const DeviceDetailsScreen({super.key, required this.posting});

  final JobPostingProvider posting;

  @override
  State<DeviceDetailsScreen> createState() => _DeviceDetailsScreenState();
}

class _DeviceDetailsScreenState extends State<DeviceDetailsScreen> {
  late final TextEditingController _model = TextEditingController(
    text: widget.posting.draft.model ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.posting.draft.description ?? '',
  );

  @override
  void dispose() {
    _model.dispose();
    _description.dispose();
    super.dispose();
  }

  void _continue() {
    // Written on the way out rather than on every keystroke: these two fields
    // feed no live rule, so notifying the whole flow per character would
    // rebuild four screens' worth of widgets to change nothing visible.
    widget.posting.setModel(_model.text);
    widget.posting.setDescription(_description.text);

    Navigator.of(context).push(
      PostingRoute<void>(
        builder: (_) => WhereAndWhenScreen(posting: widget.posting),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.posting,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final JobPostingProvider posting = widget.posting;
    final String category = posting.deviceCategory?.label ?? 'Device';

    return PostingScaffold(
      step: 4,
      title: 'Device details',
      subtitle: 'Brand and model help us match someone who knows your unit.',
      stepName: 'Details',
      ctaLabel: 'Continue',
      onCta: _continue,
      children: <Widget>[
        const PostingLabel('Device type', state: FieldState.saved),
        const SizedBox(height: AppSizes.sm),
        PostingReadOnlyField(value: category),
        const SizedBox(height: AppSizes.xl),

        // Renders the "which exact device" dropdown only where the category has
        // more than one candidate, then the brand list for whatever is chosen.
        if (posting.draft.deviceType != null)
          DeviceBrandPicker(
            category: posting.draft.deviceType!,
            deviceDetail: posting.draft.deviceDetail,
            brand: posting.draft.brand,
            onChanged: ({String? deviceDetail, String? brand}) => posting
                .setDeviceDetail(deviceDetail: deviceDetail, brand: brand),
          ),

        const SizedBox(height: AppSizes.xl),
        const PostingLabel('Model (optional)'),
        const SizedBox(height: AppSizes.sm),
        TextField(
          controller: _model,
          textCapitalization: TextCapitalization.words,
          maxLength: 60,
          decoration: const InputDecoration(
            hintText: 'e.g. IdeaPad 3 14"',
            counterText: '',
          ),
        ),

        const SizedBox(height: AppSizes.lg),
        const PostingLabel('Problem description'),
        const SizedBox(height: AppSizes.sm),
        TextField(
          controller: _description,
          maxLines: 4,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Describe what happened...',
          ),
        ),

        // The client's own words can say "basic" when the picked issue did
        // not (2026-11-16) - "needs a restart", "maluwag yung cable". Only in
        // that case: if the issue itself was basic, the card was already on
        // the previous step and the client chose, so it is not asked twice.
        // Never when the suggestion is Shop Repair (2026-11-17): a unit that
        // needs the bench is not nudged towards advice.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _description,
          builder: (BuildContext context, TextEditingValue value, Widget? _) {
            final bool wordsAreBasic =
                !posting.basicProblem &&
                posting.draft.classification?.servicePath !=
                    ServicePath.pickup &&
                BasicProblemDetector.check(description: value.text) != null;

            return AnimatedSize(
              duration: AppMotion.base,
              curve: AppMotion.standard,
              alignment: Alignment.topCenter,
              child: wordsAreBasic
                  ? Padding(
                      padding: const EdgeInsets.only(top: AppSizes.md),
                      child: BasicProblemCard(
                        communitySelected:
                            posting.draft.servicePath ==
                            ServicePath.itCommunity,
                        onTryCommunity: () => posting.overrideServicePath(
                          ServicePath.itCommunity,
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            );
          },
        ),
      ],
    );
  }
}

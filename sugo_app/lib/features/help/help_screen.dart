import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/session/session_controller.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/contact_launcher.dart';
import '../../core/utils/ui_feedback.dart';
import '../../core/widgets/sugo_app_bar.dart';
import '../../core/widgets/sugo_card.dart';
import '../../core/widgets/sugo_empty_state.dart';
import '../../core/widgets/sugo_pill.dart';
import '../../core/widgets/sugo_search_field.dart';
import '../bookings/screens/bookings_list_view.dart';

/// Which part of the app a question is about.
enum HelpTopic {
  booking('Booking'),
  tracking('Tracking'),
  payment('Payment'),
  account('Account'),
  technicians('Technicians');

  const HelpTopic(this.label);

  final String label;
}

/// One answered question.
class HelpArticle {
  const HelpArticle({
    required this.topic,
    required this.question,
    required this.answer,
  });

  final HelpTopic topic;
  final String question;
  final String answer;

  bool matches(String query) {
    final String q = query.toLowerCase();
    return question.toLowerCase().contains(q) ||
        answer.toLowerCase().contains(q) ||
        topic.label.toLowerCase().contains(q);
  }
}

/// Help & support: searchable answers, then a way to reach a person.
///
/// ## Why the answers are written here rather than fetched
///
/// They are about how SUGO works - what "matched" means, when a phone number
/// is released, who takes payment - and none of that changes per user or per
/// day. Fetching them would add a loading state, an error state and a table,
/// to deliver text that ships with the app anyway. It also means help works
/// on a phone with no signal, which is exactly when somebody is most likely to
/// be looking for it.
///
/// Every answer below describes behaviour the database actually enforces; if
/// one of those rules changes, this file is part of the change.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  /// Where to reach SUGO. A capstone project has no support desk, so this is
  /// the team's own address rather than an invented one.
  static const String supportEmail = 'support@sugo.app';

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final TextEditingController _search = TextEditingController();

  String _query = '';
  HelpTopic? _topic;
  int? _open;

  static const List<HelpArticle> _articles = <HelpArticle>[
    HelpArticle(
      topic: HelpTopic.booking,
      question: 'How do I book a technician?',
      answer:
          'Tap the + button, pick what is broken, describe the problem and add '
          'a photo if you can. SUGO ranks the three best technicians for that '
          'job and you choose one. They then accept or decline - a booking is '
          'confirmed only once somebody accepts.',
    ),
    HelpArticle(
      topic: HelpTopic.booking,
      question: 'What do the booking statuses mean?',
      answer:
          '"Finding technicians" means your job has been posted and is being '
          'matched. "Choose technician" means your top three are ready. '
          '"Waiting for acceptance" means you picked someone and they have not '
          'answered. "Confirmed" means they accepted. "In progress" means work '
          'has started, and "Completed" means it is finished and you can rate '
          'it.',
    ),
    HelpArticle(
      topic: HelpTopic.booking,
      question: 'Can I cancel a booking?',
      answer:
          'You can delete a request while nobody has taken it, and you can '
          'cancel a request a technician has not answered yet - neither counts '
          'against them. Once a technician has accepted, message them to agree '
          'what happens next; SUGO does not cancel a confirmed job from the '
          'app.',
    ),
    HelpArticle(
      topic: HelpTopic.booking,
      question: 'Something went wrong with my booking. What can I do?',
      answer:
          'Open the booking and tap "Report a problem with this booking" at '
          'the bottom - or use "Problem with a booking" below. Choose what '
          'went wrong, describe it, and add photos if you have them. A SUGO '
          'admin reviews every report, reads the chat on that booking, and '
          'writes their decision on the booking for both of you. Reports open '
          'once a technician has taken the job and close 7 days after it is '
          'completed.',
    ),
    HelpArticle(
      topic: HelpTopic.booking,
      question: 'Why only three technicians?',
      answer:
          'A shortlist is a decision you can actually make. The engine scores '
          'everyone qualified on skill match, distance, rating and '
          'availability, then shows the top three with the reasons for each '
          'score. You can still browse the full directory from "See all" on '
          'the home screen.',
    ),
    HelpArticle(
      topic: HelpTopic.tracking,
      question: 'Why can I not see my technician on a map?',
      answer:
          'Live tracking exists for workshop pickups, where your appliance '
          'travels. An on-site repair has nothing to track - the technician '
          'comes to you and fixes it there. Tracking also pauses while the '
          'unit is on the bench, because a pin that has not moved for hours '
          'looks broken rather than informative.',
    ),
    HelpArticle(
      topic: HelpTopic.tracking,
      question: 'How accurate is the ETA?',
      answer:
          'It is an estimate from distance and sampled traffic speed, not a '
          'driven route, which is why it is shown in minutes rather than as an '
          'exact arrival time. If the technician falls behind the original '
          'estimate you are told, along with the reason when we can establish '
          'one.',
    ),
    HelpArticle(
      topic: HelpTopic.payment,
      question: 'How do I pay?',
      answer:
          'Directly to your technician. SUGO does not take payment, hold money '
          'or charge a service fee. The budget you set when posting is a guide '
          'for matching; the final amount is agreed with the technician after '
          'they have seen the problem.',
    ),
    HelpArticle(
      topic: HelpTopic.payment,
      question: 'Is there a receipt?',
      answer:
          'Every booking has a summary - open it and tap "View booking '
          'summary". It records what was done, by whom, when, and the budget '
          'that was set. It is not a payment receipt, because the payment does '
          'not go through SUGO.',
    ),
    HelpArticle(
      topic: HelpTopic.technicians,
      question: 'Are technicians verified?',
      answer:
          'Yes. Every technician submits a government ID and an NBI clearance, '
          'which the SUGO team reviews, and passes an assessment in their '
          'specialisation before they can take work. The blue tick on a '
          'profile means that review passed.',
    ),
    HelpArticle(
      topic: HelpTopic.technicians,
      question: 'When can I call my technician?',
      answer:
          'Once a booking is confirmed. Before that you can message them '
          'through the app, but phone numbers are not released - in either '
          'direction - while people are still only browsing.',
    ),
    HelpArticle(
      topic: HelpTopic.technicians,
      question: 'What does "on vacation" mean?',
      answer:
          'The technician has marked days off. They still appear in your '
          'matches so you can see who is out there, but they cannot be booked '
          'until they are back, and the card tells you the date.',
    ),
    HelpArticle(
      topic: HelpTopic.account,
      question: 'Why can I not change my name?',
      answer:
          'Your name is the one on the ID the review team verified. Letting it '
          'be edited afterwards would make verification meaningless. Your '
          'photo, addresses and notification settings are all yours to change.',
    ),
    HelpArticle(
      topic: HelpTopic.account,
      question: 'My registration is still "pending review".',
      answer:
          'A person checks every ID. Until that is done you can sign in but '
          'not book, and you will be routed to the waiting screen. If it has '
          'been more than two working days, contact support below.',
    ),
    HelpArticle(
      topic: HelpTopic.account,
      question: 'How do I stop notifications?',
      answer:
          'Settings → Notifications. You can mute categories inside the app, '
          'and turn off push for this phone entirely. Your phone\'s own '
          'settings also have a SUGO notification permission.',
    ),
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<HelpArticle> get _visible => _articles
      .where((HelpArticle a) => _topic == null || a.topic == _topic)
      .where((HelpArticle a) => _query.length < 2 || a.matches(_query))
      .toList(growable: false);

  /// The person's bookings, to pick the one the problem is about. Tapping a
  /// booking opens it, and its "Report a problem" is at the bottom.
  void _chooseBookingToReport() {
    final bool technician =
        context.read<SessionController>().profile?.isTechnician ?? false;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.background,
          appBar: const SugoAppBar(title: 'Which booking?'),
          body: SafeArea(
            child: BookingsListView(
              role: technician ? BookingsRole.technician : BookingsRole.client,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _email(String subject) async {
    final Uri uri = Uri(
      scheme: 'mailto',
      path: HelpScreen.supportEmail,
      queryParameters: <String, String>{'subject': subject},
    );
    final bool opened = await ContactLauncher.openUri(uri);
    if (!opened && mounted) {
      UiFeedback.showInfo(
        context,
        'No mail app found. Write to ${HelpScreen.supportEmail}.',
        actionLabel: 'OK',
        onAction: () {},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<HelpArticle> visible = _visible;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const SugoAppBar(title: 'Help & support'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.screenPadding,
          AppSizes.md,
          AppSizes.screenPadding,
          AppSizes.xxl,
        ),
        children: <Widget>[
          SugoSearchField(
            controller: _search,
            hint: 'Search help',
            onChanged: (String value) => setState(() {
              _query = value.trim();
              _open = null;
            }),
          ),
          const SizedBox(height: AppSizes.md),
          SizedBox(
            height: AppSizes.filterTabHeight,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                SugoPill(
                  label: 'All',
                  selected: _topic == null,
                  onTap: () => setState(() => _topic = null),
                ),
                for (final HelpTopic topic in HelpTopic.values) ...<Widget>[
                  const SizedBox(width: AppSizes.sm),
                  SugoPill(
                    label: topic.label,
                    selected: _topic == topic,
                    onTap: () => setState(
                      () => _topic = _topic == topic ? null : topic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          if (visible.isEmpty)
            SugoEmptyState(
              icon: Icons.search_off_rounded,
              title: 'No answer for "$_query"',
              message:
                  'Try a different word, or send us the question directly and '
                  'a person will answer it.',
              actionLabel: 'Contact support',
              onAction: () => _email('SUGO question: $_query'),
            )
          else
            for (int i = 0; i < visible.length; i++)
              _FaqTile(
                article: visible[i],
                expanded: _open == i,
                onTap: () => setState(() => _open = _open == i ? null : i),
              ),
          const SizedBox(height: AppSizes.xl),
          const SectionHeader(
            title: 'Still stuck?',
            subtitle: 'A person reads every one of these',
          ),
          const SizedBox(height: AppSizes.md),
          _ContactCard(
            icon: Icons.mail_outline_rounded,
            title: 'Contact support',
            body: 'Questions about your account, a booking or a technician.',
            action: 'Email us',
            onTap: () => _email('SUGO support request'),
          ),
          const SizedBox(height: AppSizes.md),
          // A dispute about a job belongs on that job, where the chat, the
          // photos and the timeline are - so this opens the bookings to pick
          // one, rather than an email with none of that attached.
          _ContactCard(
            icon: Icons.report_problem_outlined,
            title: 'Problem with a booking',
            body:
                'Work not fixed, a no-show, a price that was not agreed. Pick '
                'the booking, then tap "Report a problem" at the bottom.',
            action: 'Choose booking',
            onTap: _chooseBookingToReport,
          ),
          const SizedBox(height: AppSizes.md),
          _ContactCard(
            icon: Icons.bug_report_outlined,
            title: 'Report an app problem',
            body:
                'Something in the app is broken or behaved unexpectedly. Tell '
                'us what you were doing when it happened.',
            action: 'Report',
            onTap: () => _email('SUGO problem report'),
          ),
          const SizedBox(height: AppSizes.md),
          _ContactCard(
            icon: Icons.shield_outlined,
            title: 'Report a safety concern',
            body:
                'Anything about a technician or a client that worries you. '
                'These are read first.',
            action: 'Report',
            onTap: () => _email('SUGO safety concern'),
          ),
        ],
      ),
    );
  }
}

/// A question that opens to its answer.
class _FaqTile extends StatelessWidget {
  const _FaqTile({
    required this.article,
    required this.expanded,
    required this.onTap,
  });

  final HelpArticle article;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      margin: const EdgeInsets.only(bottom: AppSizes.sm),
      padding: const EdgeInsets.all(AppSizes.md + 2),
      elevation: SugoElevation.sm,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  article.question,
                  style: AppTextStyles.titleSmall.copyWith(fontSize: 15),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: AppMotion.base,
                curve: AppMotion.standard,
                child: const Icon(
                  Icons.expand_more_rounded,
                  size: 22,
                  color: AppColors.hint,
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: AppMotion.base,
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSizes.sm),
                    child: Text(article.answer, style: AppTextStyles.body),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: AppSizes.iconTile,
            height: AppSizes.iconTile,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppSizes.radius),
            ),
            child: Icon(icon, size: 21, color: AppColors.primary),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: AppTextStyles.titleSmall),
                const SizedBox(height: 3),
                Text(body, style: AppTextStyles.micro),
                const SizedBox(height: AppSizes.sm),
                Row(
                  children: <Widget>[
                    Text(
                      action,
                      style: AppTextStyles.micro.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.secondaryDark,
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: AppColors.secondaryDark,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

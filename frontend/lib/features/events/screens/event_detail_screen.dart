import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

final _eventDetailProv = FutureProvider.family.autoDispose<Map<String,dynamic>, String>((ref, id) async {
  final api = ref.read(apiServiceProvider);
  final [er, ar] = await Future.wait([
    api.get('/events/$id'),
    api.get('/events/$id/attendees', q: {'limit': '20'}),
  ]);
  return {
    'event': EventModel.fromJson(Map<String,dynamic>.from(er.data['event'] ?? {})),
    'attendees': ar.data['attendees'] ?? [],
    'going_count': er.data['event']?['going_count'] ?? 0,
    'interested_count': er.data['event']?['interested_count'] ?? 0,
  };
});

class EventDetailScreen extends ConsumerStatefulWidget {
  final String eventId;
  const EventDetailScreen({super.key, required this.eventId});
  @override ConsumerState<EventDetailScreen> createState() => _S();
}
class _S extends ConsumerState<EventDetailScreen> {
  String? _myStatus; bool _submitting = false;

  Future<void> _rsvp(String status) async {
    setState(() { _submitting = true; _myStatus = status; });
    try {
      await ref.read(apiServiceProvider).post('/events/${widget.eventId}/attend', data: {'status': status});
      ref.refresh(_eventDetailProv(widget.eventId));
    } catch (_) { setState(() => _myStatus = null); }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_eventDetailProv(widget.eventId));
    final me   = ref.watch(currentUserProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return data.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator(color: AppTheme.orange))),
      error: (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('$e'))),
      data: (d) {
        final event     = d['event'] as EventModel;
        final attendees = d['attendees'] as List;
        final goingCnt  = d['going_count'] as int;
        final intCnt    = d['interested_count'] as int;
        final isCreator = event.creatorId == me?.id;
        final status    = _myStatus ?? event.myStatus;
        final start     = DateTime.tryParse(event.startDatetime) ?? DateTime.now();
        final end       = event.endDatetime != null ? DateTime.tryParse(event.endDatetime!) : null;
        final isPast    = start.isBefore(DateTime.now());
        final fmt       = DateFormat('EEEE, MMMM d, y');
        final timeFmt   = DateFormat('h:mm a');

        return Scaffold(
          body: CustomScrollView(slivers: [
            SliverAppBar(
              expandedHeight: 240,
              pinned: true,
              leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
              actions: [
                if (isCreator) IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () {}),
                IconButton(icon: const Icon(Icons.share_rounded), onPressed: () {}),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(fit: StackFit.expand, children: [
                  event.coverUrl != null
                    ? CachedNetworkImage(imageUrl: event.coverUrl!, fit: BoxFit.cover)
                    : Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]))),
                  Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.7)]))),
                  Positioned(bottom: 20, left: 20, right: 20, child: Text(event.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, height: 1.2), maxLines: 3)),
                ]),
              ),
            ),

            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Date & Time
              _InfoCard(Icons.calendar_month_rounded, 'Date & Time', '${fmt.format(start)}\n${timeFmt.format(start)}${end != null ? ' – ${timeFmt.format(end)}' : ''}', dark),
              const SizedBox(height: 10),

              // Location
              if (event.location != null) GestureDetector(
                onTap: () => launchUrl(Uri.parse('https://maps.google.com/?q=${Uri.encodeComponent(event.location!)}'), mode: LaunchMode.externalApplication),
                child: _InfoCard(Icons.location_on_rounded, 'Location', event.location!, dark, trailing: const Icon(Icons.directions_rounded, color: AppTheme.orange, size: 20)),
              ),

              // Online link
              if (event.onlineLink != null) GestureDetector(
                onTap: () => launchUrl(Uri.parse(event.onlineLink!), mode: LaunchMode.externalApplication),
                child: _InfoCard(Icons.videocam_rounded, 'Online Event', event.onlineLink!.replaceAll('https://', ''), dark, trailing: const Icon(Icons.open_in_new_rounded, color: AppTheme.orange, size: 18)),
              ),

              if (event.location != null || event.onlineLink != null) const SizedBox(height: 10),

              // About
              if (event.description != null && event.description!.isNotEmpty) ...[
                const Text('About', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                const SizedBox(height: 8),
                Text(event.description!, style: const TextStyle(fontSize: 14, height: 1.6)),
                const SizedBox(height: 16),
              ],

              // Creator
              Row(children: [
                AppAvatar(url: event.creator?.avatarUrl, size: 40, username: event.creator?.username),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Hosted by', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(event.creator?.displayName ?? event.creator?.username ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                ])),
                TextButton(onPressed: () => context.push('/profile/${event.creatorId}'), child: const Text('View', style: TextStyle(color: AppTheme.orange))),
              ]),
              const SizedBox(height: 16),

              // Attendance stats
              Row(children: [
                _AttStat(goingCnt.toString(), 'Going'),
                const SizedBox(width: 20),
                _AttStat(intCnt.toString(), 'Interested'),
                const Spacer(),
                GestureDetector(onTap: () => context.push('/event/${widget.eventId}/attendees'), child: const Text('See all →', style: TextStyle(color: AppTheme.orange, fontSize: 13, fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 12),

              // Attendee avatars
              if (attendees.isNotEmpty) Row(children: [
                ...attendees.take(6).toList().asMap().entries.map((e) => Transform.translate(offset: Offset(e.key * -10.0, 0), child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: dark ? AppTheme.dBg : Colors.white, width: 2)), child: AppAvatar(url: e.value['avatar_url'], size: 36, username: e.value['username'])))),
                if (attendees.length > 6) Transform.translate(offset: const Offset(-60, 0), child: Container(width: 36, height: 36, decoration: BoxDecoration(color: AppTheme.orangeSurf, shape: BoxShape.circle, border: Border.all(color: dark ? AppTheme.dBg : Colors.white, width: 2)), child: Center(child: Text('+${attendees.length - 6}', style: const TextStyle(color: AppTheme.orange, fontSize: 10, fontWeight: FontWeight.w700))))),
              ]),
              const SizedBox(height: 20),

              // RSVP Section
              if (!isPast) ...[
                const Text('Will you attend?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: ElevatedButton.icon(
                    onPressed: _submitting ? null : () => _rsvp(status == 'going' ? 'not_going' : 'going'),
                    icon: Icon(status == 'going' ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded, size: 18),
                    label: Text(status == 'going' ? '✓ Going' : 'Going', style: const TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: status == 'going' ? AppTheme.orange : null,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(
                    onPressed: _submitting ? null : () => _rsvp(status == 'interested' ? 'not_going' : 'interested'),
                    icon: Icon(status == 'interested' ? Icons.star_rounded : Icons.star_border_rounded, size: 18, color: status == 'interested' ? AppTheme.orange : null),
                    label: Text(status == 'interested' ? 'Interested' : 'Interested', style: TextStyle(fontWeight: FontWeight.w700, color: status == 'interested' ? AppTheme.orange : null)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: status == 'interested' ? AppTheme.orange : Colors.grey, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  )),
                ]),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text('Invite Friends', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                ),
              ] else Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.event_busy_rounded, color: Colors.grey), SizedBox(width: 8), Text('This event has ended', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600))])),

              const SizedBox(height: 30),
            ]))),
          ]),
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon; final String title, content; final bool dark; final Widget? trailing;
  const _InfoCard(this.icon, this.title, this.content, this.dark, {this.trailing});
  @override Widget build(BuildContext _) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: dark ? AppTheme.dDiv : const Color(0xFFEEEEEE))),
    child: Row(children: [
      Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: AppTheme.orange, size: 20)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 11, color: dark ? AppTheme.dSub : AppTheme.lSub, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(content, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.4)),
      ])),
      if (trailing != null) trailing!,
    ]),
  );
}

class _AttStat extends StatelessWidget {
  final String count, label;
  const _AttStat(this.count, this.label);
  @override Widget build(BuildContext _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(count, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: AppTheme.orange)), Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))]);
}

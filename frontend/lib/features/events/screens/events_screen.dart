import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

final _eventsProv = FutureProvider.autoDispose<Map<String,dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  final [up, past] = await Future.wait([
    api.get('/events', q: {'filter': 'upcoming', 'limit': '20'}),
    api.get('/events', q: {'filter': 'past',     'limit': '10'}),
  ]);
  return {
    'upcoming': (up.data['events']   as List? ?? []).map((e) => EventModel.fromJson(Map<String,dynamic>.from(e))).toList(),
    'past':     (past.data['events'] as List? ?? []).map((e) => EventModel.fromJson(Map<String,dynamic>.from(e))).toList(),
  };
});

class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});
  @override ConsumerState<EventsScreen> createState() => _S();
}
class _S extends ConsumerState<EventsScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  @override void initState() { super.initState(); _tc = TabController(length: 3, vsync: this); }
  @override void dispose() { _tc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_eventsProv);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Events', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        actions: [
          IconButton(icon: const Icon(Icons.add_circle_rounded, color: AppTheme.orange, size: 28), onPressed: () => context.push('/create-event'), tooltip: 'Create Event'),
        ],
        bottom: TabBar(
          controller: _tc, indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey, labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          tabs: const [Tab(text: 'Upcoming'), Tab(text: 'Past'), Tab(text: 'My Events')],
        ),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
        error: (e, _) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.event_busy_rounded, size: 64, color: Colors.grey), const SizedBox(height: 12),
          ElevatedButton(onPressed: () => ref.refresh(_eventsProv), child: const Text('Retry')),
        ])),
        data: (d) {
          final upcoming = d['upcoming'] as List<EventModel>;
          final past     = d['past']     as List<EventModel>;
          return TabBarView(controller: _tc, children: [
            _EventList(events: upcoming, emptyLabel: 'No upcoming events', onRefresh: () => ref.refresh(_eventsProv)),
            _EventList(events: past, emptyLabel: 'No past events', onRefresh: () => ref.refresh(_eventsProv)),
            _MyEvents(onRefresh: () => ref.refresh(_eventsProv)),
          ]);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/create-event'),
        backgroundColor: AppTheme.orange,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Create', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _EventList extends StatelessWidget {
  final List<EventModel> events; final String emptyLabel; final VoidCallback onRefresh;
  const _EventList({required this.events, required this.emptyLabel, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.event_rounded, size: 72, color: Colors.grey), const SizedBox(height: 16),
      Text(emptyLabel, style: const TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8), const Text('Events from people you follow will appear here', style: TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
      const SizedBox(height: 16), ElevatedButton.icon(onPressed: () => context.push('/create-event'), icon: const Icon(Icons.add_rounded), label: const Text('Create Event')),
    ]));

    return RefreshIndicator(color: AppTheme.orange, onRefresh: () async => onRefresh(), child: ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: events.length,
      itemBuilder: (_, i) => _EventCard(event: events[i]),
    ));
  }
}

class _EventCard extends ConsumerStatefulWidget {
  final EventModel event;
  const _EventCard({required this.event});
  @override ConsumerState<_EventCard> createState() => _ECS();
}
class _ECS extends ConsumerState<_EventCard> {
  String? _myStatus;
  @override void initState() { super.initState(); _myStatus = widget.event.myStatus; }

  Future<void> _rsvp(String status) async {
    setState(() => _myStatus = status);
    try {
      await ref.read(apiServiceProvider).post('/events/${widget.event.id}/attend', data: {'status': status});
    } catch (e) {
      if (mounted) setState(() => _myStatus = widget.event.myStatus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e    = widget.event;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final now  = DateTime.now();
    final start = DateTime.tryParse(e.startDatetime) ?? now;
    final isToday = start.year == now.year && start.month == now.month && start.day == now.day;
    final isPast  = start.isBefore(now);
    final fmt = DateFormat('EEE, MMM d  •  h:mm a');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: dark ? AppTheme.dCard : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: InkWell(
        onTap: () => context.push('/event/${e.id}'),
        borderRadius: BorderRadius.circular(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Cover image
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Stack(children: [
              e.coverUrl != null
                ? CachedNetworkImage(imageUrl: e.coverUrl!, height: 150, width: double.infinity, fit: BoxFit.cover)
                : Container(height: 150, decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark])), child: const Center(child: Icon(Icons.event_rounded, color: Colors.white54, size: 48))),

              // Today badge
              if (isToday) Positioned(top: 10, left: 10, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)), child: const Text('TODAY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)))),

              // Past badge
              if (isPast) Positioned.fill(child: Container(decoration: BoxDecoration(color: Colors.black.withOpacity(0.45)), child: const Center(child: Text('ENDED', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, fontSize: 18))))),

              // Type badge
              Positioned(top: 10, right: 10, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(e.eventType == 'online' ? Icons.videocam_rounded : Icons.place_rounded, color: Colors.white, size: 13),
                  const SizedBox(width: 4),
                  Text(e.eventType == 'online' ? 'Online' : 'In-Person', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              )),
            ]),
          ),

          Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Date
            Row(children: [
              const Icon(Icons.calendar_today_rounded, size: 14, color: AppTheme.orange),
              const SizedBox(width: 5),
              Text(fmt.format(start), style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w600, fontSize: 12)),
            ]),
            const SizedBox(height: 6),

            // Title
            Text(e.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),

            // Creator
            Row(children: [
              AppAvatar(url: e.creator?.avatarUrl, size: 22, username: e.creator?.username),
              const SizedBox(width: 6),
              Text('By ${e.creator?.displayName ?? e.creator?.username ?? 'Unknown'}', style: TextStyle(fontSize: 12, color: dark ? AppTheme.dSub : AppTheme.lSub)),
            ]),
            const SizedBox(height: 6),

            // Location
            if (e.location != null) Row(children: [Icon(Icons.location_on_rounded, size: 14, color: dark ? AppTheme.dSub : AppTheme.lSub), const SizedBox(width: 4), Expanded(child: Text(e.location!, style: TextStyle(fontSize: 12, color: dark ? AppTheme.dSub : AppTheme.lSub), maxLines: 1, overflow: TextOverflow.ellipsis))]),
            if (e.location != null) const SizedBox(height: 8),

            // Description
            if (e.description != null) Text(e.description!, style: TextStyle(fontSize: 13, color: dark ? AppTheme.dSub : AppTheme.lSub, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),

            // Attendees + RSVP
            Row(children: [
              // Going count
              Row(children: [
                const Icon(Icons.people_rounded, size: 16, color: AppTheme.orange),
                const SizedBox(width: 4),
                Text('${e.goingCount} going', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                if (e.interestedCount > 0) ...[const Text(' · ', style: TextStyle(color: Colors.grey)), Text('${e.interestedCount} interested', style: const TextStyle(fontSize: 12, color: Colors.grey))],
              ]),
              const Spacer(),

              // RSVP buttons
              if (!isPast) Row(children: [
                _RSVPBtn(status: 'going',      label: '✓ Going',      active: _myStatus == 'going',      color: AppTheme.orange, onTap: () => _rsvp('going')),
                const SizedBox(width: 6),
                _RSVPBtn(status: 'interested', label: '★ Interested', active: _myStatus == 'interested', color: Colors.grey,      onTap: () => _rsvp('interested')),
              ]),
            ]),
          ])),
        ]),
      ),
    );
  }
}

class _RSVPBtn extends StatelessWidget {
  final String status, label; final bool active; final Color color; final VoidCallback onTap;
  const _RSVPBtn({required this.status, required this.label, required this.active, required this.color, required this.onTap});
  @override Widget build(BuildContext _) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: active ? color : Colors.transparent,
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: active ? Colors.white : color, fontWeight: FontWeight.w600, fontSize: 12)),
    ),
  );
}

class _MyEvents extends ConsumerStatefulWidget {
  final VoidCallback onRefresh;
  const _MyEvents({required this.onRefresh});
  @override ConsumerState<_MyEvents> createState() => _MES();
}
class _MES extends ConsumerState<_MyEvents> {
  List<dynamic> _e = []; bool _l = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { final r = await ref.read(apiServiceProvider).get('/events', q: {'filter': 'mine'}); setState(() { _e = r.data['events'] ?? []; _l = false; }); } catch (_) { setState(() => _l = false); }
  }
  @override Widget build(BuildContext context) => _l ? const Center(child: CircularProgressIndicator(color: AppTheme.orange))
    : _e.isEmpty ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.event_note_rounded, size: 64, color: Colors.grey), const SizedBox(height: 16), const Text("You haven't created any events", style: TextStyle(color: Colors.grey, fontSize: 16)), const SizedBox(height: 16), ElevatedButton.icon(onPressed: () => context.push('/create-event'), icon: const Icon(Icons.add_rounded), label: const Text('Create Your First Event'))]))
    : RefreshIndicator(color: AppTheme.orange, onRefresh: _load, child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: _e.length, itemBuilder: (_, i) {
        final e = _e[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          leading: ClipRRect(borderRadius: BorderRadius.circular(10), child: e['cover_url'] != null ? CachedNetworkImage(imageUrl: e['cover_url'], width: 60, height: 60, fit: BoxFit.cover) : Container(width: 60, height: 60, color: AppTheme.orangeSurf, child: const Icon(Icons.event_rounded, color: AppTheme.orange))),
          title: Text(e['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${e['going_count'] ?? 0} going', style: const TextStyle(color: AppTheme.orange, fontSize: 12)),
          trailing: PopupMenuButton<String>(onSelected: (v) {
            if (v == 'view') context.push('/event/${e['id']}');
            if (v == 'edit') context.push('/create-event', extra: {'event': e});
            if (v == 'delete') _delete(e['id']);
          }, itemBuilder: (_) => [const PopupMenuItem(value: 'view', child: Text('View')), const PopupMenuItem(value: 'edit', child: Text('Edit')), const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red)))]),
          onTap: () => context.push('/event/${e['id']}'),
        );
      }));
  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Delete Event?'), content: const Text('This cannot be undone.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red)))]));
    if (ok != true) return;
    await ref.read(apiServiceProvider).delete('/events/$id').catchError((_){});
    _load();
  }
}

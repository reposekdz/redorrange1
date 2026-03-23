import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

class GiftSheetWidget extends ConsumerStatefulWidget {
  final String receiverId, receiverName;
  final String? receiverAvatar;
  final String contextType;
  final String? contextId;

  const GiftSheetWidget({
    super.key,
    required this.receiverId,
    required this.receiverName,
    this.receiverAvatar,
    this.contextType = 'live',
    this.contextId,
  });

  @override
  ConsumerState<GiftSheetWidget> createState() => _S();
}

class _S extends ConsumerState<GiftSheetWidget> {
  List<dynamic> _gifts = [];
  int _userCoins = 0;
  bool _loading = true, _sending = false;
  String? _selectedGiftId;
  int _qty = 1;
  String _activeCategory = 'All';
  static const _cats = ['All', 'basic', 'premium', 'special', 'seasonal'];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await ref.read(apiServiceProvider).get('/gifts');
      setState(() {
        _gifts      = r.data['gifts'] ?? [];
        _userCoins  = r.data['user_coins'] as int? ?? 0;
        _loading    = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  List<dynamic> get _filtered => _activeCategory == 'All' ? _gifts : _gifts.where((g) => g['category'] == _activeCategory).toList();

  Future<void> _send() async {
    if (_selectedGiftId == null) return;
    final gift = _gifts.firstWhere((g) => g['id'] == _selectedGiftId);
    final totalCost = (gift['coin_price'] as int? ?? 0) * _qty;
    if (_userCoins < totalCost) {
      Navigator.pop(context);
      context.push('/wallet');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Insufficient coins. Buy more!')));
      return;
    }
    setState(() => _sending = true);
    try {
      final r = await ref.read(apiServiceProvider).post('/gifts/send', data: {
        'receiver_id': widget.receiverId,
        'gift_id': _selectedGiftId,
        'quantity': _qty,
        'context_type': widget.contextType,
        if (widget.contextId != null) 'context_id': widget.contextId,
      });
      if (r.data['success'] == true) {
        setState(() => _userCoins = r.data['new_balance'] as int? ?? _userCoins);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [Text('${gift['emoji']} Gift sent to ${widget.receiverName}!'), const Spacer(), Icon(Icons.check_circle_rounded, color: Colors.white)]),
            backgroundColor: Colors.green,
          ));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final dark       = Theme.of(context).brightness == Brightness.dark;
    final selectedGift = _selectedGiftId != null ? _gifts.firstWhere((g) => g['id'] == _selectedGiftId, orElse: () => null) : null;

    return Container(
      decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(22))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 12), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),

        // Header
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
          AppAvatar(url: widget.receiverAvatar, size: 36, username: widget.receiverName),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Send gift to ${widget.receiverName}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            Row(children: [const Icon(Icons.monetization_on_rounded, color: AppTheme.orange, size: 14), const SizedBox(width: 4), Text('Your balance: ${FormatUtils.count(_userCoins)} coins', style: const TextStyle(color: AppTheme.orange, fontSize: 12, fontWeight: FontWeight.w600))]),
          ])),
          TextButton.icon(onPressed: () { Navigator.pop(context); context.push('/wallet'); }, icon: const Icon(Icons.add_circle_rounded, size: 16), label: const Text('Buy', style: TextStyle(fontSize: 12))),
        ])),

        const SizedBox(height: 8),

        // Category filter
        SizedBox(height: 34, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _cats.length, itemBuilder: (_, i) {
          final cat = _cats[i]; final sel = cat == _activeCategory;
          return GestureDetector(onTap: () => setState(() { _activeCategory = cat; _selectedGiftId = null; }), child: AnimatedContainer(duration: const Duration(milliseconds: 150), margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: sel ? AppTheme.orange : AppTheme.orangeSurf, borderRadius: BorderRadius.circular(18)), child: Text(cat == 'All' ? 'All' : '${cat[0].toUpperCase()}${cat.substring(1)}', style: TextStyle(color: sel ? Colors.white : AppTheme.orange, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, fontSize: 12))));
        })),

        const SizedBox(height: 12),

        // Gifts grid
        SizedBox(height: 220, child: _loading ? const Center(child: CircularProgressIndicator(color: AppTheme.orange)) : GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          scrollDirection: Axis.horizontal,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.85),
          itemCount: _filtered.length,
          itemBuilder: (_, i) {
            final g = _filtered[i]; final sel = _selectedGiftId == g['id'];
            final canAfford = _userCoins >= (g['coin_price'] as int? ?? 0) * _qty;
            return GestureDetector(
              onTap: () => setState(() => _selectedGiftId = sel ? null : g['id']),
              child: AnimatedContainer(duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: sel ? AppTheme.orange : (dark ? AppTheme.dInput : const Color(0xFFF8F8F8)),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: sel ? AppTheme.orange : Colors.transparent, width: 2),
                  boxShadow: sel ? [BoxShadow(color: AppTheme.orange.withOpacity(0.3), blurRadius: 10)] : [],
                ),
                padding: const EdgeInsets.all(8),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(g['emoji'] ?? '🎁', style: const TextStyle(fontSize: 32)),
                  const SizedBox(height: 4),
                  Text(g['name'] ?? '', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: sel ? Colors.white : null), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.monetization_on_rounded, color: sel ? Colors.white70 : (canAfford ? AppTheme.orange : Colors.grey), size: 11),
                    const SizedBox(width: 2),
                    Text('${g['coin_price']}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sel ? Colors.white70 : (canAfford ? AppTheme.orange : Colors.grey))),
                  ]),
                ]),
              ),
            );
          },
        )),

        // Selected gift footer
        if (selectedGift != null) Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Text('${selectedGift['emoji']} ${selectedGift['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            const Text('Qty:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Row(children: [
              GestureDetector(onTap: () { if (_qty > 1) setState(() => _qty--); }, child: Container(width: 28, height: 28, decoration: const BoxDecoration(color: AppTheme.orange, shape: BoxShape.circle), child: const Icon(Icons.remove_rounded, color: Colors.white, size: 16))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('$_qty', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              GestureDetector(onTap: () => setState(() => _qty++), child: Container(width: 28, height: 28, decoration: const BoxDecoration(color: AppTheme.orange, shape: BoxShape.circle), child: const Icon(Icons.add_rounded, color: Colors.white, size: 16))),
            ]),
            const Spacer(),
            Text('= ${(selectedGift['coin_price'] as int? ?? 0) * _qty} coins', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w800, fontSize: 14)),
          ]),
        ),

        // Send button
        Padding(padding: EdgeInsets.fromLTRB(12, 10, 12, MediaQuery.of(context).viewInsets.bottom + 16), child: SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: (_selectedGiftId == null || _sending) ? null : _send,
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          child: _sending ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)), SizedBox(width: 8), Text('Sending...')])
            : Text(selectedGift != null ? '🎁 Send ${selectedGift['emoji']} Gift' : 'Select a gift', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ))),
      ]),
    );
  }
}

// ── Static helper to show gift sheet
void showGiftSheet(BuildContext context, {required String receiverId, required String receiverName, String? receiverAvatar, String contextType = 'live', String? contextId}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => GiftSheetWidget(receiverId: receiverId, receiverName: receiverName, receiverAvatar: receiverAvatar, contextType: contextType, contextId: contextId),
  );
}

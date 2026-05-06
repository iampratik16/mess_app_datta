import 'package:flutter/foundation.dart';

import '../../../core/errors/api_error.dart';
import '../domain/media_models.dart';
import 'media_api.dart';

/// In-process vault index: every screen that lists the caller's
/// uploads (Media tab, Vault picker) reads from this one source so
/// they stay consistent without polling the network on every navigation.
///
/// Why a local cache exists at all: the live backend doesn't currently
/// expose `GET /media/` (the listing endpoint shipped with prompt 7
/// but isn't deployed yet). Without a cache, the Media tab + Vault
/// picker would both look empty after a tab switch even though the
/// user just uploaded. The cache is also the right thing to keep when
/// the endpoint does land — it avoids a refetch on every push.
///
/// Strategy: best-effort fetch from `GET /media/`, then merge
/// server rows over local rows by id. If the endpoint isn't there
/// (404) we keep the local-only state; if it is, server is the truth.
class MediaVaultStore {
  MediaVaultStore._();
  static final MediaVaultStore instance = MediaVaultStore._();

  final ValueNotifier<List<MediaFile>> items = ValueNotifier<List<MediaFile>>(const []);
  bool _serverFetchedOnce = false;

  void add(MediaFile m) {
    final next = [m, ...items.value.where((x) => x.id != m.id)];
    items.value = next;
  }

  void remove(String id) {
    items.value = items.value.where((x) => x.id != id).toList();
  }

  /// Pull the caller's uploads from the server and merge into the
  /// local index. Safe to call repeatedly; the server is authoritative
  /// for any id it returns and local-only rows (e.g. just-uploaded in
  /// this session, before the index update propagates) are preserved.
  ///
  /// `force` re-runs even if we've fetched before — used by pull-to-
  /// refresh and the picker's refresh action.
  Future<void> refreshFromServer(MediaApi api, {bool force = false}) async {
    if (_serverFetchedOnce && !force) return;
    try {
      final rows = await api.listVault(limit: 100);
      final byId = <String, MediaFile>{
        for (final m in items.value) m.id: m,
      };
      for (final m in rows) {
        byId[m.id] = m;
      }
      // Sort newest-first by createdAt so picker grids render in a
      // predictable order regardless of which source contributed which row.
      final merged = byId.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      items.value = merged;
      _serverFetchedOnce = true;
    } on ApiError {
      // 404 / 401 / network: keep whatever we have locally. Caller can
      // still display + send any items uploaded this session.
    }
  }
}

import '../../../core/errors/api_error.dart';
import '../../groups/data/groups_api.dart';
import '../../groups/domain/group_models.dart';

/// Direct-message helper — layered on top of the group API because the
/// backend currently ships only group conversations.
///
/// A DM between users A and B is a group named `dm:{minId}:{maxId}` with
/// two members. Naming is deterministic so opening a DM is idempotent: the
/// repository finds the existing group or creates it.
class DmRepository {
  static const String dmPrefix = 'dm:';

  final GroupsApi _groupsApi;

  DmRepository() : _groupsApi = GroupsApi();

  /// Returns the canonical DM group name for a pair of user ids.
  static String dmName(String a, String b) {
    final lo = a.compareTo(b) < 0 ? a : b;
    final hi = a.compareTo(b) < 0 ? b : a;
    return '$dmPrefix$lo:$hi';
  }

  /// Returns true for a group whose name marks it as a DM.
  static bool isDmGroup(Group g) => g.name.startsWith(dmPrefix);

  /// Extract the other user id from a `dm:{a}:{b}` group name. Returns null
  /// if the name isn't a valid DM marker.
  static String? otherUserId(Group g, String me) {
    if (!isDmGroup(g)) return null;
    final parts = g.name.substring(dmPrefix.length).split(':');
    if (parts.length != 2) return null;
    if (parts[0] == me) return parts[1];
    if (parts[1] == me) return parts[0];
    return null;
  }

  /// Find or create the DM group for (me, other). The other user is added
  /// as a member if necessary. Returns the group (ready to open a chat in).
  Future<Group> openDm({required String meId, required String otherId}) async {
    final name = dmName(meId, otherId);

    // 1. Look for an existing DM group in the caller's groups.
    final existing = await _groupsApi.listGroups(limit: 200);
    Group? match;
    for (final g in existing) {
      if (g.name == name) {
        match = g;
        break;
      }
    }

    match ??= await _groupsApi.createGroup(name: name, mode: 'simple');

    // 2. Ensure the counterpart is a member. addMember is idempotent
    //    server-side (service returns the existing row if present).
    try {
      await _groupsApi.addMember(
        groupId: match.id,
        userId: otherId,
        role: 'member',
      );
    } on ApiError catch (_) {
      // Already-member responses come back as 2xx/idempotent, but in the
      // rare case the server returns a conflict we swallow and proceed.
    }

    return match;
  }

  /// List the caller's DM groups (those whose name starts with `dm:`).
  Future<List<Group>> listDmGroups() async {
    final groups = await _groupsApi.listGroups(limit: 200);
    return groups.where(isDmGroup).toList();
  }
}

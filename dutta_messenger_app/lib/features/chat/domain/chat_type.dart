/// Identifies which kind of conversation a [ChatScreen] is rendering.
/// Used to gate AppBar actions, header taps, and the composer:
///
/// - [dm]      one-to-one direct message. No "Members" action; tapping the
///             title opens the other user's profile sheet.
/// - [group]   multi-member group (any [Group.mode]). "Members" action
///             opens [GroupMembersScreen].
/// - [channel] broadcast channel. Members action is labelled "Subscribers";
///             non-admins see a muted "Only admins can post" composer.
enum ChatType { dm, group, channel }

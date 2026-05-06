import 'dart:async';

/// What kind of session-ending event the app shell should react to.
enum AuthEvent {
  /// Refresh terminally failed — the refresh token expired, was revoked,
  /// or the user was deactivated. Surface "Your session expired."
  sessionExpired,

  /// The server returned a 403 with an error code that says the user's
  /// access has been revoked at the institution / role level. Surface
  /// "Your access has been revoked."
  forbidden,

  /// The user tapped "Sign out" themselves. The app shell still tears
  /// down WS / FCM / tokens via the same code path, but no toast is
  /// shown — they know what they did.
  userLoggedOut,
}

/// Single, app-wide bus that the Dio interceptor and the user-initiated
/// logout button both publish to, and that the shell ([main.dart])
/// listens to exactly once.
///
/// Pre-existing logout paths (e.g. ProfileScreen's sign-out) used to do
/// "WS disconnect → FCM revoke → clear tokens → push LoginScreen" inline.
/// That worked for the user-initiated case but left no path for the
/// "refresh token expired in the background" case to also pivot the UI —
/// the audit's CRITICAL #1. Funneling everything through this bus means
/// there is one teardown sequence, used by all three triggers.
class AuthEvents {
  AuthEvents._();
  static final AuthEvents instance = AuthEvents._();

  final StreamController<AuthEvent> _ctrl =
      StreamController<AuthEvent>.broadcast();

  Stream<AuthEvent> get stream => _ctrl.stream;

  void emit(AuthEvent event) {
    if (!_ctrl.isClosed) _ctrl.add(event);
  }
}

/// Backend error codes that mean the user's session is over even though
/// the JWT itself decoded fine — the account / role / institution was
/// disabled mid-session. Treat these 403s as a forced logout.
///
/// PERMISSION_DENIED is intentionally NOT in this list: it's the generic
/// "this user can't do this thing" error (e.g. non-admin trying to invite
/// a user) and must not kick the whole session out.
const Set<String> sessionEndingForbiddenCodes = {
  'SESSION_REVOKED',
  'USER_DEACTIVATED',
  'USER_DELETED',
  'ACCOUNT_DISABLED',
  'INSTITUTION_DEACTIVATED',
};

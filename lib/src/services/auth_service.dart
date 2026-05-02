import 'package:shared_preferences/shared_preferences.dart';

enum AuthMode { undecided, guest, authenticated }

class AuthSession {
  final AuthMode mode;
  final String? userEmail;

  const AuthSession({required this.mode, this.userEmail});
}

class AuthService {
  static const _authModeKey = 'auth_mode';
  static const _userEmailKey = 'auth_user_email';

  Future<AuthSession> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final rawMode = prefs.getString(_authModeKey);
    final userEmail = prefs.getString(_userEmailKey);

    return AuthSession(
      mode: _fromStorage(rawMode),
      userEmail: userEmail,
    );
  }

  Future<void> continueAsGuest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authModeKey, 'guest');
    await prefs.remove(_userEmailKey);
  }

  Future<void> signIn({required String userEmail}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authModeKey, 'authenticated');
    await prefs.setString(_userEmailKey, userEmail);
  }

  Future<void> signOutToGuest() async {
    await continueAsGuest();
  }

  AuthMode _fromStorage(String? value) {
    switch (value) {
      case 'guest':
        return AuthMode.guest;
      case 'authenticated':
        return AuthMode.authenticated;
      default:
        return AuthMode.undecided;
    }
  }
}

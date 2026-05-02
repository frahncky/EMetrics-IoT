import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';

class AuthState {
  final bool isLoading;
  final AuthMode mode;
  final String? userEmail;

  const AuthState({
    required this.isLoading,
    required this.mode,
    this.userEmail,
  });

  AuthState copyWith({
    bool? isLoading,
    AuthMode? mode,
    String? userEmail,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      mode: mode ?? this.mode,
      userEmail: userEmail ?? this.userEmail,
    );
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(authServiceProvider));
});

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;

  AuthNotifier(this._authService)
      : super(const AuthState(isLoading: true, mode: AuthMode.undecided)) {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final session = await _authService.restoreSession();
    state = AuthState(
      isLoading: false,
      mode: session.mode,
      userEmail: session.userEmail,
    );
  }

  Future<void> continueAsGuest() async {
    await _authService.continueAsGuest();
    state = const AuthState(isLoading: false, mode: AuthMode.guest);
  }

  Future<void> signIn({required String email, required String password}) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
      throw Exception('Informe um e-mail valido.');
    }
    if (password.trim().isEmpty) {
      throw Exception('Informe a senha.');
    }

    await _authService.signIn(userEmail: trimmedEmail);
    state = AuthState(
      isLoading: false,
      mode: AuthMode.authenticated,
      userEmail: trimmedEmail,
    );
  }

  Future<void> signOutToGuest() async {
    await _authService.signOutToGuest();
    state = const AuthState(isLoading: false, mode: AuthMode.guest);
  }
}

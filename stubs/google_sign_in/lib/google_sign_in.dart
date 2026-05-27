class GoogleSignIn {
  GoogleSignIn({List<String>? scopes, this.clientId, this.serverClientId})
    : scopes = scopes ?? const [];

  final List<String> scopes;
  final String? clientId;
  final String? serverClientId;

  Future<GoogleSignInAccount?> signIn() async => null;

  Future<void> signOut() async {}
}

class GoogleSignInAccount {
  const GoogleSignInAccount({required this.email, this.displayName});

  final String email;
  final String? displayName;
}

enum AppleIDAuthorizationScopes { email, fullName }

enum AuthorizationErrorCode {
  canceled,
  notInteractive,
  notHandled,
  invalidResponse,
  failed,
  unknown,
}

class AuthorizationCredentialAppleID {
  const AuthorizationCredentialAppleID({
    required this.userIdentifier,
    this.email,
    this.givenName,
    this.familyName,
  });

  final String? userIdentifier;
  final String? email;
  final String? givenName;
  final String? familyName;
}

class SignInWithAppleAuthorizationException implements Exception {
  const SignInWithAppleAuthorizationException(this.code, [this.message = '']);

  final AuthorizationErrorCode code;
  final String message;

  @override
  String toString() {
    final suffix = message.isEmpty ? '' : ': $message';
    return 'SignInWithAppleAuthorizationException($code)$suffix';
  }
}

class SignInWithAppleNotSupportedException implements Exception {
  const SignInWithAppleNotSupportedException([this.message = '']);

  final String message;

  @override
  String toString() {
    final suffix = message.isEmpty ? '' : ': $message';
    return 'SignInWithAppleNotSupportedException$suffix';
  }
}

class SignInWithApple {
  const SignInWithApple._();

  static Future<bool> isAvailable() async => false;

  static Future<AuthorizationCredentialAppleID> getAppleIDCredential({
    required List<AppleIDAuthorizationScopes> scopes,
    String? webAuthenticationOptions,
    String? nonce,
    String? state,
  }) async {
    throw const SignInWithAppleNotSupportedException(
      'Sign in with Apple is not available in the CN build.',
    );
  }
}

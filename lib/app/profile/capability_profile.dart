enum AuthProviderType { phoneSms, emailOtp, google, apple }

enum OcrProviderType { legacyCnOcr, googleVisionGemini, googleExpenseParser }

enum AiProviderType { legacyCnAi, gemini }

enum StockMarketScope { cn, us }

class CapabilityProfile {
  const CapabilityProfile({
    required this.authProviders,
    required this.ocrProvider,
    required this.aiProvider,
    required this.stockMarketScope,
    required this.featureFlags,
  });

  final List<AuthProviderType> authProviders;
  final OcrProviderType ocrProvider;
  final AiProviderType aiProvider;
  final StockMarketScope stockMarketScope;
  final Map<String, bool> featureFlags;

  bool isEnabled(String key) => featureFlags[key] ?? false;
}

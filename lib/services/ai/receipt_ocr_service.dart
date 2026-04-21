abstract class ReceiptOcrService {
  Future<String?> recognizeText(List<int> imageBytes);

  Future<String?> recognizeReceipt(List<int> imageBytes);
}

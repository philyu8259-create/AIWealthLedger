import 'package:equatable/equatable.dart';

abstract class InputParserService {
  Future<List<ParsedResult>> parseInput(String input);
}

class ParsedResult extends Equatable {
  final double amount;
  final String category;
  final String note;
  final String type;

  const ParsedResult({
    required this.amount,
    required this.category,
    required this.note,
    required this.type,
  });

  @override
  List<Object?> get props => [amount, category, note, type];
}

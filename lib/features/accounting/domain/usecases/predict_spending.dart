import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/entities.dart';

/// AI 消费预测结果
class SpendingPrediction extends Equatable {
  final double predictedTotalExpense;
  final double predictedDailyAverage;
  final Map<String, double> categoryPredictions;
  final Map<String, double> budgetRecommendations;
  final List<String> warnings;
  final String aiInsight;

  const SpendingPrediction({
    required this.predictedTotalExpense,
    required this.predictedDailyAverage,
    required this.categoryPredictions,
    required this.budgetRecommendations,
    required this.warnings,
    required this.aiInsight,
  });

  @override
  List<Object?> get props => [
    predictedTotalExpense,
    predictedDailyAverage,
    categoryPredictions,
    budgetRecommendations,
    warnings,
    aiInsight,
  ];
}

/// AI 消费预测 UseCase
abstract class SpendingPredictionService {
  Future<Either<String, SpendingPrediction>> predictSpending({
    required List<AccountEntry> entries,
    required double currentMonthExpense,
  });
}

class PredictSpending
    implements UseCase<SpendingPrediction, PredictSpendingParams> {
  PredictSpending(this._predictionService);

  final SpendingPredictionService _predictionService;

  @override
  Future<Either<String, SpendingPrediction>> call(
    PredictSpendingParams params,
  ) async {
    return _predictionService.predictSpending(
      entries: params.entries,
      currentMonthExpense: params.currentMonthExpense,
    );
  }
}

class PredictSpendingParams extends Equatable {
  final List<AccountEntry> entries;
  final double currentMonthExpense;

  const PredictSpendingParams({
    required this.entries,
    required this.currentMonthExpense,
  });

  @override
  List<Object?> get props => [entries, currentMonthExpense];
}

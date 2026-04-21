import 'package:dartz/dartz.dart';

/// 基础 UseCase 接口
abstract class UseCase<Result, Params> {
  Future<Either<String, Result>> call(Params params);
}

/// 无参数时使用此类
class NoParams {
  const NoParams();
}

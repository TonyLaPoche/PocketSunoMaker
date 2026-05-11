abstract class Failure {
  const Failure(this.message, {this.cause});

  final String message;
  final Object? cause;
}

final class StorageFailure extends Failure {
  const StorageFailure(super.message, {super.cause});
}

final class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {super.cause});
}

final class UnknownFailure extends Failure {
  const UnknownFailure(super.message, {super.cause});
}

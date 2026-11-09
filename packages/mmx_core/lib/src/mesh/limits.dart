/// Default allocation budget for operators that multiply geometry. Callers may
/// choose a different face budget explicitly; vertex storage is bounded too.
const defaultMaximumGeneratedFaces = 2000000;

void checkGeneratedSize(
    int faces, int vertices, int maximumFaces, String operation) {
  if (maximumFaces <= 0 || maximumFaces > 100000000) {
    throw ArgumentError('maximumFaces must be between 1 and 100000000');
  }
  if (faces < 0 ||
      vertices < 0 ||
      faces > maximumFaces ||
      vertices > maximumFaces * 3) {
    throw StateError('$operation exceeds the output budget of $maximumFaces '
        'faces or ${maximumFaces * 3} vertices');
  }
}

/// Checks before multiplying, so even huge repeat counts cannot wrap an int.
int checkedFaceProduct(
    int faces, int multiplier, int maximumFaces, String operation) {
  checkGeneratedSize(faces, 0, maximumFaces, operation);
  if (multiplier < 0 ||
      (multiplier > 0 && faces > maximumFaces ~/ multiplier)) {
    throw StateError(
        '$operation exceeds the output budget of $maximumFaces faces');
  }
  return faces * multiplier;
}

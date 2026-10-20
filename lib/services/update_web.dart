bool get updatesSupported => false;

bool assetMatches(String name) => false;

Future<String> downloadUpdate({
  required String url,
  required String fileName,
  required int expectedSize,
  required String? expectedSha256,
  required void Function(double) onProgress,
}) =>
    throw UnsupportedError('Updates gibt es im Browser automatisch.');

Future<void> installUpdate(String path) async {}

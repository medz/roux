// ignore_for_file: public_member_api_docs

const int slashCode = 47;

/// Splits a path into segments, dropping the leading slash and any trailing empty segment.
List<String> splitPath(String path) {
  if (path == '/') return const [];
  return path.split('/').sublist(1);
}

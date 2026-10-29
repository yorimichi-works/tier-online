import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'text_fetcher.dart';

enum AppleArtworkKind { album, song }

@immutable
class AppleArtwork {
  const AppleArtwork({
    required this.id,
    required this.title,
    required this.artist,
    required this.artworkUrl,
    required this.kind,
  });

  final String id;
  final String title;
  final String artist;

  /// HTTPS mzstatic URL resized to [AppleArtworkService.cellPixels].
  final String artworkUrl;
  final AppleArtworkKind kind;

  String get credit => artist.isEmpty ? title : '$artist – $title';
}

/// Port of oshireco's `MusicArtworkResolver.itunes`: accepts only Apple
/// artwork hosts, forces HTTPS and rewrites the `100x100bb.jpg` suffix.
abstract final class AppleArtworkResolver {
  static String? resize(String? rawUrl, int pixels) {
    final uri = secureAppleUri(rawUrl);
    if (uri == null) return null;
    final path = uri.path.replaceFirst(
      RegExp(r'/\d+x\d+[^/]*\.(jpg|jpeg|png)$', caseSensitive: false),
      '/${pixels}x${pixels}bb.jpg',
    );
    return uri.replace(path: path).toString();
  }

  static Uri? secureAppleUri(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasAuthority) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    final host = uri.host.toLowerCase();
    final isApple =
        host == 'mzstatic.com' ||
        host.endsWith('.mzstatic.com') ||
        host == 'itunes.apple.com' ||
        host.endsWith('.itunes.apple.com') ||
        host == 'music.apple.com' ||
        host.endsWith('.music.apple.com');
    return isApple ? uri.replace(scheme: 'https') : null;
  }

  static bool isAppleArtwork(String? url) {
    final uri = secureAppleUri(url);
    return uri != null &&
        (uri.host == 'mzstatic.com' || uri.host.endsWith('.mzstatic.com'));
  }
}

/// Album/song artwork search through the public iTunes Search API (no API
/// key). Apple asks for roughly 20 calls per minute at most, so results are
/// cached per query and the UI only searches on submit.
class AppleArtworkService {
  AppleArtworkService({Future<String> Function(Uri url)? fetcher})
    : _fetch = fetcher ?? fetchText;

  static const cellPixels = 600;

  final Future<String> Function(Uri url) _fetch;
  final _cache = <String, List<AppleArtwork>>{};

  /// iTunes storefront for a tier-online region code.
  static String countryFor(String region) => switch (region) {
    'JP' || 'KR' || 'TW' || 'HK' || 'US' || 'GB' || 'BR' => region,
    _ => 'US',
  };

  static String langFor(String country) => switch (country) {
    'JP' => 'ja_jp',
    _ => 'en_us',
  };

  Future<List<AppleArtwork>> search(
    String query, {
    required AppleArtworkKind kind,
    required String region,
  }) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    final country = countryFor(region);
    final key = '$country|${kind.name}|${term.toLowerCase()}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final url = Uri.https('itunes.apple.com', '/search', {
      'term': term,
      'country': country,
      'media': 'music',
      'entity': kind == AppleArtworkKind.album ? 'album' : 'song',
      'limit': '30',
      'lang': langFor(country),
    });
    final results = parse(
      jsonDecode(await _fetch(url)) as Map<String, dynamic>,
      kind,
    );
    _cache[key] = results;
    return results;
  }

  @visibleForTesting
  static List<AppleArtwork> parse(
    Map<String, dynamic> json,
    AppleArtworkKind kind,
  ) {
    final seen = <String>{};
    final results = <AppleArtwork>[];
    for (final raw in json['results'] as List<dynamic>? ?? const []) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final isAlbum =
          item['wrapperType'] == 'collection' &&
          item['collectionType'] == 'Album';
      final isSong = item['wrapperType'] == 'track' && item['kind'] == 'song';
      if (kind == AppleArtworkKind.album ? !isAlbum : !isSong) continue;
      final id =
          (kind == AppleArtworkKind.album
                  ? item['collectionId']
                  : item['trackId'])
              ?.toString() ??
          '';
      final title =
          (kind == AppleArtworkKind.album
                  ? item['collectionName']
                  : item['trackName'])
              as String? ??
          '';
      final artworkUrl = AppleArtworkResolver.resize(
        (item['artworkUrl100'] ?? item['artworkUrl60']) as String?,
        cellPixels,
      );
      if (id.isEmpty || title.isEmpty || artworkUrl == null) continue;
      // The same jacket often appears for a single and its tracks.
      if (!seen.add(artworkUrl)) continue;
      results.add(
        AppleArtwork(
          id: id,
          title: title,
          artist: item['artistName'] as String? ?? '',
          artworkUrl: artworkUrl,
          kind: kind,
        ),
      );
    }
    return results;
  }
}

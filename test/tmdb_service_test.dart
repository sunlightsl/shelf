import 'package:flutter_test/flutter_test.dart';
import 'package:local_library/services/tmdb_service.dart';

void main() {
  group('TMDBService.extractQuery', () {
    test('removes file extension', () {
      expect(TMDBService.extractQuery('Inception.mp4'), 'Inception');
    });

    test('removes resolution markers', () {
      expect(TMDBService.extractQuery('Inception.1080p.mp4'), 'Inception');
      expect(TMDBService.extractQuery('Movie.4K.HDR.mp4'), 'Movie HDR');
    });

    test('removes source markers', () {
      expect(TMDBService.extractQuery('Film.BluRay.x264.mkv'), 'Film');
      expect(TMDBService.extractQuery('Show.WEB-DL.HDTV.mkv'), 'Show');
    });

    test('removes year in parentheses', () {
      expect(TMDBService.extractQuery('Movie (2023).mp4'), 'Movie');
    });

    test('removes season/episode codes', () {
      expect(TMDBService.extractQuery('Show.S01E05.mp4'), 'Show');
    });

    test('replaces dots and underscores with spaces', () {
      expect(TMDBService.extractQuery('The_Dark_Knight.mp4'), 'The Dark Knight');
      expect(TMDBService.extractQuery('Inception.2010.mp4'), 'Inception');
    });
  });

  group('TMDBService.posterUrl', () {
    test('builds correct poster URL', () {
      expect(
        TMDBService.posterUrl('/abc123.jpg'),
        'https://image.tmdb.org/t/p/w500/abc123.jpg',
      );
    });

    test('returns null for empty path', () {
      expect(TMDBService.posterUrl(null), null);
      expect(TMDBService.posterUrl(''), null);
    });

    test('supports custom size', () {
      expect(
        TMDBService.posterUrl('/abc.jpg', size: 'original'),
        'https://image.tmdb.org/t/p/original/abc.jpg',
      );
    });
  });
}

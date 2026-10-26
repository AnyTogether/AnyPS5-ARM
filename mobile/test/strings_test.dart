import 'package:anyps5_remote/strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('capitals keep the dot on the Turkish i, and English is as always', () {
    expect(
      Strings.turkish.upper('Arkadaşlık istekleri'),
      'ARKADAŞLIK İSTEKLERİ',
    );
    expect(Strings.turkish.upper('Platin'), 'PLATİN');
    expect(Strings.turkish.upper('Oynandı'), 'OYNANDI');
    expect(Strings.english.upper('Friend requests'), 'FRIEND REQUESTS');
  });
}

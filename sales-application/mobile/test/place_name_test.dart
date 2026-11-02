import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:sales_tracker_app/place_name.dart';

void main() {
  test('area then city (#91)', () {
    expect(
        placeLabel(Placemark(subLocality: 'Baner', locality: 'Pune')),
        'Baner, Pune');
  });

  test('falls back to the street, then the district', () {
    expect(
        placeLabel(Placemark(
            thoroughfare: 'FC Road', subAdministrativeArea: 'Pune District')),
        'FC Road, Pune District');
  });

  test('the same name is not repeated', () {
    expect(placeLabel(Placemark(name: 'Pune', locality: 'Pune')), 'Pune');
  });

  test('nothing known gives null, so coordinates are shown instead', () {
    expect(placeLabel(Placemark(subLocality: '  ', locality: '')), isNull);
  });
}

/// Decodes a Google "encoded polyline" string into a list of `[lat, lng]`
/// pairs. Standard algorithm:
/// https://developers.google.com/maps/documentation/utilities/polylinealgorithm
List<List<double>> decodePolyline(String encoded) {
  final points = <List<double>>[];
  final len = encoded.length;
  var index = 0;
  var lat = 0;
  var lng = 0;

  while (index < len) {
    var shift = 0;
    var result = 0;
    int b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lng += dlng;

    points.add([lat / 1e5, lng / 1e5]);
  }
  return points;
}

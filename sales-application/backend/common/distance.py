"""How far someone travelled, from the points their day already produced.

A rep's day is a line through dots: where they checked in, each place they
visited in time order, and where they checked out. Measuring that line is the
whole travel-allowance calculation - there is no separate tracking to build.

Two ways to measure it, behind one function so the choice can change later
without touching anything that calls it:

  * STRAIGHT     - haversine. Free, instant, works offline, no API key. Short
                   of real road distance, so a factor is applied.
  * ROAD         - a routing service. Accurate, costs a request, needs network.

Start on STRAIGHT. Switch by changing TRAVEL_DISTANCE_MODE in settings; stored
figures are not recalculated, which is deliberate - see `freeze` in the module
docstring of whatever writes the claim.
"""
import math

from django.conf import settings

# Roads bend, cars cannot fly. A straight line between two points is short of
# the distance actually driven; this scales it up. 1.3 is the usual convention
# for urban driving. Tune it against a handful of real journeys before trusting
# it with money.
DEFAULT_ROAD_FACTOR = 1.3

# One leg longer than this is treated as a bad GPS reading rather than a real
# journey. A phone that briefly reports the wrong continent would otherwise
# turn into a payout. Flagged, not silently dropped.
MAX_PLAUSIBLE_LEG_KM = 300.0

EARTH_RADIUS_KM = 6371.0088


def haversine_km(a, b):
    """Great-circle distance in km between two (lat, lng) pairs.

    Pure arithmetic - no network, no key, no cost. Accurate to well under a
    metre at city scale, which is far finer than the GPS fixes feeding it.
    """
    lat1, lng1 = float(a[0]), float(a[1])
    lat2, lng2 = float(b[0]), float(b[1])

    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)

    h = (math.sin(dlat / 2) ** 2
         + math.cos(math.radians(lat1))
         * math.cos(math.radians(lat2))
         * math.sin(dlng / 2) ** 2)

    return 2 * EARTH_RADIUS_KM * math.asin(math.sqrt(h))


def day_points(attendance, visits):
    """The dots of one working day, in the order they happened.

    `visits` must already be ordered by `visited_at`. Insertion order is not
    good enough: a visit recorded offline and synced later would otherwise sit
    in the wrong place in the route and inflate the distance.

    An open day (no check-out yet) simply ends at the last visit.
    """
    points = [(attendance.check_in_lat, attendance.check_in_lng)]
    points += [(v.lat, v.lng) for v in visits]
    if attendance.check_out_at is not None:
        points.append((attendance.check_out_lat, attendance.check_out_lng))
    return points


def straight_line_km(points, road_factor=None):
    """Sum of the legs, scaled up for roads. Free, and the default."""
    if road_factor is None:
        road_factor = getattr(settings, "TRAVEL_ROAD_FACTOR",
                              DEFAULT_ROAD_FACTOR)
    raw = sum(haversine_km(a, b) for a, b in zip(points, points[1:]))
    return raw * road_factor


def implausible_legs(points):
    """Legs long enough to be a GPS error rather than a journey.

    Returned rather than raised: the day still has a distance, it just needs a
    person to look at it before it is paid.
    """
    flagged = []
    for i, (a, b) in enumerate(zip(points, points[1:])):
        km = haversine_km(a, b)
        if km > MAX_PLAUSIBLE_LEG_KM:
            flagged.append({"leg": i, "km": round(km, 1),
                            "from": a, "to": b})
    return flagged


# Google caps a single Routes request at an origin, a destination and this many
# intermediate waypoints. A day with more stops than that is thinned before
# sending (see _trim_waypoints); losing a mid-point slightly understates the
# route, which is the safe direction to err with money.
MAX_ROUTE_INTERMEDIATES = 25

ROUTES_ENDPOINT = (
    "https://routes.googleapis.com/directions/v2:computeRoutes"
)


def _trim_waypoints(points):
    """Reduce an over-long list to origin + <=25 intermediates + destination.

    Keeps the first and last (they are the day's start and end, which must not
    move) and drops evenly spaced points from the middle. Only runs when a day
    has more than 27 stops, which in practice it never does.
    """
    if len(points) <= MAX_ROUTE_INTERMEDIATES + 2:
        return points
    first, last = points[0], points[-1]
    middle = points[1:-1]
    step = len(middle) / MAX_ROUTE_INTERMEDIATES
    kept = [middle[int(i * step)] for i in range(MAX_ROUTE_INTERMEDIATES)]
    return [first] + kept + [last]


def _waypoint(point):
    lat, lng = float(point[0]), float(point[1])
    return {"location": {"latLng": {"latitude": lat, "longitude": lng}}}


def road_km(points):
    """Real driving distance in km from the Google Routes API.

    Called only when TRAVEL_DISTANCE_MODE is "road". Sends the whole day as one
    request - origin, destination, and the stops between as intermediates - and
    reads the total distance back. One request per rep per day.

    Raises on any failure (no key, network error, unexpected response) rather
    than returning a wrong number; travelled_km() catches that and falls back
    to the straight-line estimate, so a routing outage never stops a day being
    costed, it only marks the figure as an estimate.
    """
    import requests

    api_key = getattr(settings, "GOOGLE_ROUTES_API_KEY", "")
    if not api_key:
        raise RuntimeError("GOOGLE_ROUTES_API_KEY is not set.")

    points = _trim_waypoints(points)
    body = {
        "origin": _waypoint(points[0]),
        "destination": _waypoint(points[-1]),
        "travelMode": "DRIVE",
    }
    if len(points) > 2:
        body["intermediates"] = [_waypoint(p) for p in points[1:-1]]

    response = requests.post(
        ROUTES_ENDPOINT,
        json=body,
        headers={
            "Content-Type": "application/json",
            "X-Goog-Api-Key": api_key,
            # Ask for only the one field we use, which Routes bills more
            # cheaply than a full response.
            "X-Goog-FieldMask": "routes.distanceMeters",
        },
        timeout=getattr(settings, "GOOGLE_ROUTES_TIMEOUT", 10),
    )
    response.raise_for_status()

    routes = response.json().get("routes") or []
    if not routes or "distanceMeters" not in routes[0]:
        raise ValueError("Routes API returned no distance.")
    return routes[0]["distanceMeters"] / 1000.0


def measure_day(attendance, visits):
    """Everything the allowance needs to know about one day's travel.

    Returns a dict, not just a number, because what is *stored* on a claim is
    more than the distance: which method produced it, whether it is a fallback
    estimate rather than a measurement, and which legs looked like GPS errors.

      {
        "km": float,            # distance, by the configured method
        "method": "road"|"straight",
        "is_estimate": bool,    # True when road was asked for but fell back
        "flagged_legs": [...],  # legs too long to be real travel
      }

    A day with fewer than two points (no check-out yet, or no movement) is a
    zero-distance straight-line day - never an estimate, never flagged.
    """
    points = day_points(attendance, visits)
    if len(points) < 2:
        return {"km": 0.0, "method": "straight",
                "is_estimate": False, "flagged_legs": []}

    flagged = implausible_legs(points)
    mode = getattr(settings, "TRAVEL_DISTANCE_MODE", "straight")

    if mode == "road":
        try:
            return {"km": road_km(points), "method": "road",
                    "is_estimate": False, "flagged_legs": flagged}
        except Exception:
            # A routing outage must not stop a day being costed; it only means
            # the figure is the straight-line estimate, flagged as such.
            return {"km": straight_line_km(points), "method": "straight",
                    "is_estimate": True, "flagged_legs": flagged}

    return {"km": straight_line_km(points), "method": "straight",
            "is_estimate": False, "flagged_legs": flagged}


def travelled_km(attendance, visits):
    """The distance for one day, by whichever method is configured.

    The single entry point for callers that want only the number. Anything
    writing a claim should use measure_day(), which also reports the method,
    the estimate flag and the flagged legs.
    """
    return measure_day(attendance, visits)["km"]

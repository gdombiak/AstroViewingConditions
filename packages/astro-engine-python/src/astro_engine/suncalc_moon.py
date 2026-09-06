"""Production SunCalc lunar facts, used only by astronomy.moon_observation.

Ported from the pinned SunCalc Swift dependency's Moon, Sun, JulianDate,
ExtendedMath, Matrix, Vector, MoonPosition and MoonIllumination implementations.
Keep operation order and geocentric/refraction conventions in sync with Swift;
this is a compatibility model, not a replacement for moon_info/moon_series.

Copyright © 2021 Nikolaj Banke Jensen
Copyright (C) 2017 Richard "Shred" Körber, http://commons.shredzone.org
Modified 2026: translated the lunar observation subset from Swift to Python.
Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy at
http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.
"""
from __future__ import annotations

import math
from datetime import datetime

from math import sin, cos, sqrt, atan2, fmod, pi

PI2 = pi * 2.0
DEGREES = 180 / pi
RADIANS = pi / 180
ARCS = 3600.0 * DEGREES


def _polar(phi, theta, radius):
    cos_theta = cos(theta)
    return (radius * cos(phi) * cos_theta,
            radius * sin(phi) * cos_theta, radius * sin(theta))


def _multiply(matrix, vector):
    # Swift Matrix.multiply accumulates every row from zero, including zeros.
    result = []
    for row in matrix:
        total = 0.0
        for coefficient, component in zip(row, vector):
            total += coefficient * component
        result.append(total)
    return tuple(result)


def _coordinates(vector):
    x, y, z = vector
    phi = 0.0 if x == 0 and y == 0 else atan2(y, x)
    if phi < 0:
        phi += PI2
    p_squared = x * x + y * y
    theta = 0.0 if z == 0 and p_squared == 0 else atan2(z, sqrt(p_squared))
    return phi, theta, sqrt(x * x + y * y + z * z)


def _equatorial(vector, century):
    eps = (23.43929111 - (46.8150 + (0.00059 - 0.001813 * century)
                          * century) * century / 3600.0) * RADIANS
    c, s = cos(eps), sin(eps)
    return _multiply(((1.0, 0.0, 0.0), (0.0, c, -s), (0.0, s, c)), vector)


def _moon(century):
    t = century
    l0 = fmod(0.606433 + 1336.855225 * t, 1.0)
    l = PI2 * fmod(0.374897 + 1325.552410 * t, 1.0)
    ls = PI2 * fmod(0.993133 + 99.997361 * t, 1.0)
    d = PI2 * fmod(0.827361 + 1236.853086 * t, 1.0)
    f = PI2 * fmod(0.259086 + 1342.227825 * t, 1.0)
    d2, l2, f2 = 2.0 * d, 2.0 * l, 2.0 * f
    dl = (22640.0 * sin(l)
          - 4586.0 * sin(l - d2)
          + 2370.0 * sin(d2)
          + 769.0 * sin(l2)
          - 668.0 * sin(ls)
          - 412.0 * sin(f2)
          - 212.0 * sin(l2 - d2)
          - 206.0 * sin(l + ls - d2)
          + 192.0 * sin(l + d2)
          - 165.0 * sin(ls - d2)
          - 125.0 * sin(d)
          - 110.0 * sin(l + ls)
          + 148.0 * sin(l - ls)
          - 55.0 * sin(f2 - d2))
    s = f + (dl + 412.0 * sin(f2) + 541.0 * sin(ls)) / ARCS
    h = f - d2
    n = (-526.0 * sin(h)
         + 44.0 * sin(l + h)
         - 31.0 * sin(-l + h)
         - 23.0 * sin(ls + h)
         + 11.0 * sin(-ls + h)
         - 25.0 * sin(-l2 + f)
         + 21.0 * sin(-l + f))
    longitude = PI2 * fmod(l0 + dl / 1296.0e3, 1.0)
    latitude = (18520.0 * sin(s) + n) / ARCS
    distance = (385000.5584 - 20905.3550 * cos(l)
                - 3699.1109 * cos(d2 - l)
                - 2955.9676 * cos(d2) - 569.9251 * cos(l2))
    return _equatorial(_polar(longitude, latitude, distance), t)


def _sun(century, day_of_year):
    m = PI2 * fmod(0.993133 + 99.997361 * century, 1.0)
    longitude = PI2 * fmod(0.7859453 + m / PI2
                          + (6893.0 * sin(m) + 72.0 * sin(2.0 * m)
                             + 6191.2 * century) / 1296.0e3, 1.0)
    anomaly = PI2 * fmod((day_of_year - 5.0) / 365.256363, 1.0)
    distance = 149598000.0 * (1 - 0.016718 * cos(anomaly))
    return _equatorial(_polar(longitude, 0.0, distance), century)


def _julian(time):
    mjd = time.timestamp() / 86400.0 + 40587.0
    return mjd, (mjd - 51544.5) / 36525.0


class SunCalcMoonAstronomy:
    """Analytic provider with the same sampler protocol as the observation search."""

    def moon_horizontal(self, latitude: float, longitude: float, time: datetime):
        mjd, t = _julian(time)
        mjd0 = math.floor(mjd)
        ut = (mjd - mjd0) * 86400.0
        t0 = (mjd0 - 51544.5) / 36525.0
        gmst = (24110.54841 + 8640184.812866 * t0 + 1.0027379093 * ut
                + (0.093104 - 6.2e-6 * t) * t * t)
        sidereal = (PI2 / 86400.0) * fmod(gmst, 86400.0)
        ra, dec, distance = _coordinates(_moon(t))
        hour_angle = sidereal + longitude * RADIANS - ra
        angle = pi / 2.0 - latitude * RADIANS
        c, s = cos(angle), sin(angle)
        horizontal = _multiply(((c, 0.0, -s), (0.0, 1.0, 0.0), (s, 0.0, c)),
                               _polar(hour_angle, dec, distance))
        azimuth, geometric, distance = _coordinates(horizontal)
        refraction = (0.0 if geometric < 0 else
                      0.000296706 / math.tan(geometric + 0.00312537 / (geometric + 0.0890118)))
        return ((geometric + refraction) * DEGREES,
                fmod(azimuth * DEGREES + 180, 360), geometric, distance)

    def moon_phase(self, time: datetime) -> tuple[float, float]:
        _, t = _julian(time)
        moon = _moon(t)
        sun = _sun(t, time.timetuple().tm_yday)
        dot = moon[0] * sun[0] + moon[1] * sun[1] + moon[2] * sun[2]
        phi = pi - math.acos(dot / (_coordinates(moon)[2] * _coordinates(sun)[2]))
        cross = (moon[1] * sun[2] - moon[2] * sun[1],
                 moon[2] * sun[0] - moon[0] * sun[2],
                 moon[0] * sun[1] - moon[1] * sun[0])
        theta = _coordinates(cross)[1]
        sign = 0.0 if theta == 0 else (1.0 if theta > 0 else -1.0)
        return (1 + cos(phi)) / 2, (phi * sign) * DEGREES

"""Rejected lunar observation model, retained only as independent audit evidence.

These are the inherited Skyfield formulas. Production moon_observation now uses
SunCalc; existing moon_info/moon_series still use Skyfield unchanged.
"""
from datetime import datetime
from astro_engine.astronomy import SkyfieldAstronomy


class SkyfieldMoonReference(SkyfieldAstronomy):
    def moon_horizontal(self, latitude: float, longitude: float, time: datetime):
        """Geocentric Moon direction for `astronomy.moon_observation`.

        Returns `(refracted_altitude_degrees, azimuth_degrees, geometric_altitude_radians,
        distance_km)`. The refracted altitude and the geocentric, no-parallax model are
        exactly `moon_info`'s; the geometric altitude and distance drive the rise/set
        threshold, which SunCalc evaluates before refraction.
        """
        import numpy as np
        t = self.timescale.from_datetime(time)
        apparent = self.earth.at(t).observe(self.moon).apparent()
        ra, dec, distance = apparent.radec(epoch="date")
        hour_angle = np.radians(t.gast * 15 + longitude) - ra.radians
        phi = np.radians(latitude)
        geometric = np.arcsin(np.clip(np.sin(phi) * np.sin(dec.radians)
                              + np.cos(phi) * np.cos(dec.radians) * np.cos(hour_angle), -1, 1))
        refracted = geometric
        if geometric >= 0:
            refracted = geometric + 0.000296706 / np.tan(geometric + 0.00312537 / (geometric + 0.0890118))
        azimuth = np.arctan2(
            np.sin(hour_angle),
            np.cos(hour_angle) * np.sin(phi) - np.tan(dec.radians) * np.cos(phi),
        ) + np.pi
        azimuth = float(np.degrees(azimuth)) % 360.0
        return float(np.degrees(refracted)), azimuth, float(geometric), float(distance.km)

    def moon_phase(self, time: datetime) -> tuple[float, float]:
        """`(illuminated_fraction, signed_phase_degrees)` in the production model.

        SunCalc computes `phi = pi - elongation` geocentrically, then
        `fraction = (1 + cos phi) / 2` and signs the phase by the declination of
        `moon x sun`, which is the sign of `sin(ra_sun - ra_moon)`. Negative is
        waxing. Deriving the fraction from the same `phi` keeps phase and
        illumination internally consistent, as they are in the Swift host.
        """
        import numpy as np
        t = self.timescale.from_datetime(time)
        moon = self.earth.at(t).observe(self.moon).apparent()
        sun = self.earth.at(t).observe(self.sun).apparent()
        phi = np.pi - moon.separation_from(sun).radians
        fraction = (1 + np.cos(phi)) / 2
        difference = float(sun.radec(epoch="date")[0].radians - moon.radec(epoch="date")[0].radians)
        crossing = np.sin(difference)
        sign = 0.0 if crossing == 0 else (1.0 if crossing > 0 else -1.0)
        return float(fraction), float(np.degrees(phi) * sign)
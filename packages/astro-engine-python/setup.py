"""Build hooks for the self-contained Astro Engine release wheel.

Canonical runtime resources stay in their existing repository locations.  The
wheel build copies them into the install image so production never needs a
source checkout and the repository does not grow a second maintained copy.
"""

from __future__ import annotations

from pathlib import Path
import shutil

from setuptools import setup
from setuptools.command.build_py import build_py as _build_py


class build_py(_build_py):
    def run(self) -> None:
        super().run()
        repository = Path(__file__).resolve().parents[2]
        destination = Path(self.build_lib) / "astro_engine" / "resources"
        contracts = repository / "contracts"

        (destination / "contracts").mkdir(parents=True, exist_ok=True)
        shutil.copy2(
            contracts / "ENGINE_VERSION",
            destination / "contracts" / "ENGINE_VERSION",
        )
        shutil.copy2(
            contracts / "capabilities.yaml",
            destination / "contracts" / "capabilities.yaml",
        )
        shutil.copytree(
            contracts / "data",
            destination / "contracts" / "data",
            dirs_exist_ok=True,
        )
        shutil.copy2(
            repository
            / "apps"
            / "ios"
            / "Sources"
            / "AstroViewingConditions"
            / "Resources"
            / "LightPollution"
            / "light_pollution_global_v1.bin",
            destination / "light_pollution_global_v1.bin",
        )


setup(cmdclass={"build_py": build_py})

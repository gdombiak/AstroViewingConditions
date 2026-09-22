from __future__ import annotations

import re
from pathlib import Path
import sys


REPOSITORY = Path(__file__).resolve().parents[2]
ASTRONOMER = REPOSITORY / "astronomer"
INSTRUCTIONS = ASTRONOMER / "ASTRONOMER.md"
TOOLS = REPOSITORY / "tools" / "astronomer"

sys.path.insert(0, str(TOOLS))
from release_manifest import product_version, runtime_dependencies  # noqa: E402

SHA256_HEX = re.compile(r"\b[0-9a-f]{64}\b")
PINNED_TAG = re.compile(r"astronomer-v\d+\.\d+\.\d+")
WHEEL_NAME = re.compile(r"astro_(engine|host)-.+\.whl")


def folded(text: str) -> str:
    return " ".join(text.split())


def test_legacy_skill_and_experiment_paths_are_absent() -> None:
    assert not (REPOSITORY / ".grok" / "skills" / "astronomer").exists()
    assert not (REPOSITORY / "experiments" / "astronomer-single-md").exists()
    assert not (REPOSITORY / "Tests" / "grok").exists()
    assert not (REPOSITORY / "tools" / "grok").exists()


def test_product_version_is_committed_identity() -> None:
    assert product_version() == "0.1.2"


def test_instructions_omit_mutable_release_metadata() -> None:
    text = INSTRUCTIONS.read_text(encoding="utf-8")
    assert SHA256_HEX.search(text) is None
    assert PINNED_TAG.search(text) is None
    assert WHEEL_NAME.search(text) is None
    assert "Astronomer product version `" not in text
    assert "Astro Engine:" not in text
    assert "Astro Host:" not in text
    assert "Engine SHA-256" not in text
    assert "Host SHA-256" not in text
    version = product_version()
    assert f"astronomer-v{version}" not in text
    for pin in runtime_dependencies():
        assert pin not in text


def test_opening_identifies_astro_conditions_companion() -> None:
    _title, opening, *_rest = INSTRUCTIONS.read_text(encoding="utf-8").split("\n\n")
    opening = folded(opening)
    assert "AI astronomy expert and observing companion" in opening
    assert "same observing intelligence that powers Astro Conditions" in opening
    assert "iPhone and Apple Watch app" in opening
    assert "broader astronomy knowledge, reasoning, and web research" in opening
    assert "observing assistant" not in opening
    assert "thin wrapper" not in opening


def test_release_channel_and_manifest_authority() -> None:
    text = folded(INSTRUCTIONS.read_text(encoding="utf-8"))
    assert "gdombiak/AstroViewingConditions" in text
    assert "astronomer-vX.Y.Z" in text
    assert "draft` false" in text or "draft false" in text
    assert "prerelease` false" in text or "prerelease false" in text
    assert "astronomer-release.json" in text
    assert "Never reconstruct a manifest" in text
    assert "Do not use GitHub's `latest` flag" in text
    assert "Ignore iOS app tags, `astro-runtime-v*`" in text


def test_installed_manifest_is_local_authority_and_check_json_is_timing_only() -> None:
    text = folded(INSTRUCTIONS.read_text(encoding="utf-8"))
    assert "product/current/astronomer-release.json` is the exact validated manifest" in text
    assert "check.json` records only update-check timing" in text
    assert "must not duplicate product or component metadata" in text
    assert "last_successful_check" in text


def test_first_install_requires_four_artifacts() -> None:
    text = folded(INSTRUCTIONS.read_text(encoding="utf-8"))
    assert "Obtain all four release artifacts" in text
    assert "Do not install from this document plus two wheels alone" in text
    assert "do not invent `astronomer-release.json`" in text
    assert "exact bytes" in text


def test_update_detection_compares_only_product_version() -> None:
    text = folded(INSTRUCTIONS.read_text(encoding="utf-8"))
    assert "Compare **only** those Astronomer product versions" in text
    assert "Do not scan independently for newer Engine or Host packages" in text
    assert "This comparison only chooses how to apply the already-detected product update" in text
    assert "once every 24 hours" in text
    assert "Do not add self-update logic to Engine or Host" in text
    assert "do not create cron, systemd, or other background schedulers" in text
    assert "do not rebuild or reinstall the Python runtime" in text
    assert "remain on the prior validated" in text
    assert "never treat it as the Astronomer product version" in text
    assert "`product/current` is the only activation pointer" in text
    assert "There is no `runtime/current`" in text
    assert "product/current/runtime/.venv/bin/astro-host" in text
    assert "atomic switch of `product/current`" in text
    assert "Durable Host state" in text
    assert "do not refresh `last_successful_check`" in text


def test_routes_supported_operations_and_preserves_authority_rules() -> None:
    text = INSTRUCTIONS.read_text(encoding="utf-8")
    for operation in (
        "agent.conditions",
        "agent.places",
        "agent.locations",
        "agent.equipment",
        "agent.recommendations",
        "agent.outlook",
        "agent.batch_compare",
        "agent.sky_facts",
        "agent.eyepieces",
        "agent.optics",
    ):
        assert operation in text
    assert "agent.forecast_horizon" not in text
    assert "Do not invent targets" in text
    assert "independently rerank" in text
    assert "omission is production `any`" in text
    assert "Save only after the user confirms those facts" in text


def test_recommendation_modes_are_authoritative() -> None:
    text = INSTRUCTIONS.read_text(encoding="utf-8")
    assert '`mode` is required: `best` or `browse`' in text
    assert '`mode: "best"`' in text
    assert '`mode: "browse"`' in text
    assert "Omit rows already presented" in text
    assert "matching returned `key`" in text
    assert "Never call `best` and then drop rows locally" in text


def test_cloud_advisory_is_authoritative_and_forbids_recalculation() -> None:
    text = folded(INSTRUCTIONS.read_text(encoding="utf-8"))
    assert "night_conditions.cloud_advisory" in text
    assert "early_heavy" in text
    assert "late_heavy" in text
    assert "intermittent_heavy" in text
    assert "Never derive cloud advice from `cloud_timing`" in text
    assert "never invent a heavy-cloud interval's clock times" in text
    assert "`best_window` may be reported independently as its own authoritative fact" in text
    assert "A `cloud_timing` field in recommendations or outlook is not" in text


def test_sky_facts_routing_is_weather_independent() -> None:
    text = folded(INSTRUCTIONS.read_text(encoding="utf-8"))
    assert "agent.sky_facts" in text
    assert "does not accept `force_refresh`" in text
    assert "How dark is Home" in text
    assert "When does astronomical night start or end" in text
    assert "How is the Moon tonight from my site" in text
    assert "whether tonight is good to observe" in text
    assert "Those remain `agent.conditions`" in text
    assert "not a Bortle class" in text
    assert "`status: degraded` does not mean discard the result" in text
    assert "`status: unavailable` means no usable sky facts were produced" in text
    assert "Do not treat a failed resolution as “no astronomical night.”" in text


def test_optical_facts_stay_on_the_host_and_eyepieces_stay_separate() -> None:
    text = folded(INSTRUCTIONS.read_text(encoding="utf-8"))
    assert "agent.eyepieces" in text
    assert "agent.optics" in text
    assert "Eyepieces are not telescopes, binoculars, or smart telescopes." in text
    assert "Do not calculate them yourself" in text
    assert (
        "do not infer an unstated focal length or apparent field solely from "
        "product-name familiarity"
    ) in text
    assert "do not infer a missing focal length or apparent field from a product name" not in text
    assert "Which eyepiece to try, and how to use it, is Astronomer judgment." in text
    assert "The engine does not name a best eyepiece." in text
    assert "`equipment.match` rows remain `key`, `type`, `aperture_mm`, and `magnification`." in text
    assert "does not change target scores, order, equipment fit, or filtering" in text
    assert "Save a researched focal length or apparent field only after the user confirms" in text
    assert "instead of assuming one" in text
    assert "Saved combinations require a `visualTelescope`." in text
    assert "Binoculars and smart telescopes do not take eyepieces" in text


def test_save_with_id_carries_forward_unmentioned_confirmed_fields() -> None:
    text = folded(INSTRUCTIONS.read_text(encoding="utf-8"))
    assert "A save replaces the item." in text
    assert (
        "send every confirmed equipment field the user did not ask to remove, "
        "including aliases, focal length, binocular magnification"
    ) in text
    assert "Apparent field is an eyepiece fact, not an equipment field." in text
    assert (
        "send every confirmed eyepiece field the user did not ask to remove, "
        "including name, focal length, apparent field, and aliases."
    ) in text
    assert "Omitting `afov_degrees` or `aliases` clears them." in text
    assert "apparent field, or binocular" not in text
    assert (
        "Save with an existing `id` replaces that eyepiece; omit `id` "
        "when creating a new one."
    ) in text
    assert "Do not invent an ID for a new eyepiece." in text
    assert "Save with `id` updates that eyepiece" not in text


def test_onboarding_covers_focal_length_and_eyepieces() -> None:
    text = folded(INSTRUCTIONS.read_text(encoding="utf-8"))
    assert "For a recognizable visual telescope, also research an authoritative focal length" in text
    assert "Do not infer it from the model name." in text
    assert "ask the user rather than guessing" in text
    assert "That does not mean it accepts eyepieces." in text
    assert "Save through `agent.eyepieces` only after that confirmation." in text
    assert (
        "Do not infer an unstated focal length or apparent field solely from "
        "product-name familiarity."
    ) in text
    assert (
        "including as part of the eyepiece name they provide, is a user-provided fact "
        "and may be proposed for confirmation."
    ) in text
    assert "“8 mm Delos” states an 8 mm focal length and does not state the apparent field." in text
    assert "Do not assume an apparent field from model knowledge." in text
    assert "the user may still confirm a save without it" in text
    assert "Included-in-the-box is not evidence the user currently owns or uses them." in text
    assert "creates the user's first `visualTelescope`" in text
    assert "When that inventory is empty, make one brief offer" in text
    assert "must not block completion of the telescope save" in text
    assert "Do not offer after an update to an existing item" in text
    assert "or after saving binoculars or a smart telescope." in text
    assert "Do not persist a dismissed flag" in text


def test_eyepiece_guidance_follows_returned_targets() -> None:
    text = folded(INSTRUCTIONS.read_text(encoding="utf-8"))
    assert "saved eyepieces may add observing guidance without waiting for a second eyepiece question" in text
    assert "Target membership, order, scores, timing, and equipment fit stay exactly as returned." in text
    assert "when a visual telescope is clearly in scope" in text
    assert "do not silently choose one" in text
    assert "do not change saved equipment selection in order to give eyepiece advice" in text
    assert "Do not do this for binoculars or a smart telescope." in text
    assert "Which eyepiece to try, and how to step between them, is Astronomer judgment." in text
    assert "When the advice depends on tonight or on seeing, obtain the relevant observing facts first." in text
    assert "highest magnification for every planet" in text
    assert "An ordinary best-targets answer gets a short note" in text
    assert "do not require an optics analysis for each" in text
    assert "is a separate combined question" not in text


def test_named_place_workflow_and_presentation_boundaries() -> None:
    text = folded(INSTRUCTIONS.read_text(encoding="utf-8"))
    assert "agent.batch_compare" in text
    assert "at most eight" in text
    assert "deduplicate" in text
    assert "never substitute arbitrary grid coordinates" in text
    assert "must never rerank" in text
    assert "straight-line" in text
    assert "Unknown access remains unknown" in text
    assert "do not claim unvalidated native map" in text

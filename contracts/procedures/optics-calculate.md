# optics.calculate — telescope and eyepiece arithmetic

Capability: `optics.calculate`, `since: "1.1.0"`, `hosts: [ios, cli]`

`injected` may contain only these fields:

- `telescope_focal_length_mm`
- `eyepiece_focal_length_mm`
- `telescope_aperture_mm`
- `afov_degrees`

Every field is optional. An omitted field and an explicit JSON `null` are the
same unavailable input. Unknown keys, Booleans, non-finite numbers, and
non-positive numbers fail with `error.code = validation` and message
`invalid optics.calculate input`. Do not coerce strings and do not clamp.

`afov_degrees`, when present, must be greater than 0 and at most 180. A larger
apparent field is nonsensical for this ratio and is a validation failure.

When both focal lengths are present and valid:

- `magnification = telescope_focal_length_mm / eyepiece_focal_length_mm`

Otherwise `magnification` is `null`.

When magnification and `telescope_aperture_mm` are both available:

- `exit_pupil_mm = telescope_aperture_mm / magnification`

Otherwise `exit_pupil_mm` is `null`.

When magnification and `afov_degrees` are both available:

- `approximate_true_field_of_view_degrees = afov_degrees / magnification`

Otherwise that field is `null`. This is the simple apparent-field divided by
magnification relationship. It is not a field-stop or eyepiece-geometry model.

The result always contains exactly these three keys. The capability does not
rank eyepieces, prefer a target, look up a manufacturer, or read saved state.

# targets.filter_recommendations_by_equipment — normative stable equipment filter

Capability: `targets.filter_recommendations_by_equipment`, introduced under the
unreleased `1.0.0` identity, `hosts: [ios, cli]`, equality
`filter_recommendations_by_equipment`.

## Production behavior and boundary

The source decision is
`EquipmentSessionSelection.filteredRecommendations` after the list has already
been ranked by conditions. The portable boundary is:

```
conditions-ranked recommendation rows
+ resolved equipment requirements
+ currently selected capability facts
+ saved-inventory presence and minimum-fit policy
→ ordered subset of original {index, key} identities
```

The capability calls the same `EquipmentMatchingRules` / equipment matching
algorithm as `equipment.match`; it does not duplicate or modify matching. It
does not score, rescore, sort, normalize, reweight, truncate or deduplicate. It
makes no astronomy or weather decision. Scores, visibility windows, target
reasons, summaries, English fit explanations, display names and UI state are
absent, so hosts map returned indices back to their original recommendation
objects.

Session mechanics remain host-only: all-equipment/custom mode, toggles, the
custom selected-ID set, ensuring at least one selection, reconciliation after
inventory changes, persistence and presentation copy. In production, naked eye
is included alongside saved inventory in all-equipment mode. Custom mode uses
only explicit selections; if a toggle empties it, the host restores naked eye.
Reconciliation intersects custom IDs with the available set and likewise
restores naked eye when empty. `minimumFitAfterInventoryTransition` resets the UI
threshold to `any` only when saved inventory transitions from nonempty to empty;
it is host session-state management, not part of this stateless filter.

The dashboard first obtains a globally conditions-ranked pool bounded by the
existing host production service limit of 100, then applies this equipment
filter to the whole returned pool. Presentation then applies the five-row
dashboard limit. Therefore a passing row inside the 100-row pool can survive
when earlier rows fail, while a candidate beyond that pre-existing pool is
intentionally not considered. The 100-row candidate-pool bound is host
production composition behavior, not an engine transport cap; this capability
introduces no count limit into the business decision. Here, filtering "before
result-count truncation" means before downstream/user-facing truncation, not
before the host's existing candidate-pool bound. Source inspection establishes
the upstream 100-row behavior; the host regression only needs the existing
sixth-row case to distinguish filtering before the five-row presentation limit.

## Input

The normal envelope has `capability` plus `injected` with exactly:

- `has_saved_inventory`: JSON boolean. This distinguishes no saved inventory
  from a valid naked-eye-only selected capability set.
- `minimum_fit`: exactly `any`, `challengingOrBetter`, `goodOrBetter`, or
  `excellentOnly`.
- `capabilities`: ordered selected-capability array. Each row has exactly
  `key`, `type`, `aperture_mm`, `magnification`. Types and measurement semantics
  are identical to `equipment.match`; keys must be nonempty and unique.
- `candidates`: the existing conditions-ranked order. Each row has exactly
  `key`, `is_planet`, `requirement`. Candidate keys are nonempty but need not be
  unique. `requirement` has exactly the complete resolved requirement key set
  emitted by `targets.requirements`; enum, null, numeric, range and smart/EAA
  pair validation match `equipment.match`.

Unknown or missing fields fail. JSON booleans are not numbers. Provided numbers
must be finite and have absolute value at most `1e9`. Candidate and capability
arrays each have a 1,440-row cap checked before iteration. Exceeding one returns
`sample_cap`; other malformed input returns `validation` with message
`invalid targets.filter_recommendations_by_equipment input`.

All transport facts are validated even when the typed decision bypasses
matching. This keeps bypass from weakening the public schema.

## Decision

1. If `has_saved_inventory` is false, return every candidate identity in input
   order. The threshold and selected capabilities cannot filter anything.
2. Otherwise, if `minimum_fit == any`, return every candidate identity in input
   order without running equipment matching.
3. Otherwise, for each candidate in input order, rank the selected capabilities
   with the existing `equipment.match` rules using its resolved `requirement`
   and `is_planet` fact.
4. If no selected capability produces a best result, reject the candidate.
5. Include the candidate exactly when its best level satisfies:

| Threshold | Included levels |
|---|---|
| `any` | `excellent`, `good`, `challenging`, `poor` (bypass) |
| `challengingOrBetter` | `excellent`, `good`, `challenging` |
| `goodOrBetter` | `excellent`, `good` |
| `excellentOnly` | `excellent` |

Selected capability input order cannot change the best fit because the existing
matching total order uses level, preference, aperture, magnification and stable
key. Fit reason, observing mode, other-suitable capabilities and English
explanation do not participate in threshold filtering; only the best level does.

## Output and identity

Success is `{"selected": [{"index": 0, "key": "moon"}]}`. `index` is the
original candidate position and is authoritative. `key` is echoed and never a
sort or deduplication key. Duplicate target IDs or window keys remain separate
rows, including when both survive. Survivors retain their exact relative order.
An empty selected array is success.

Equality is exact for array order, index, key, error code and error message.

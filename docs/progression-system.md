# Progression System

This document is the source of truth for how PowerJack decides the next planned version of a lift.

Progression runs when the app creates a future program week. It looks at the same lift from the previous program weeks, the user's logged sets, and the pain and effort feedback for that lift. The system only changes planned sets, reps, and weight for the newly created week.

## Decision Order

PowerJack checks each lift in this order and stops at the first matching rule.

1. If the lift was skipped because a manual check-in is still pending, carry the held prescription forward and keep the manual check-in pending.
2. If pain was 4 or 5, repeat the completed sets and require a manual check-in before the next lift can be logged.
3. If any working set was below the exercise's minimum hypertrophy reps, keep successful sets, keep the first under-minimum set, and plan that under-minimum set at the minimum rep target.
4. If pain was 3, repeat the completed sets.
5. If effort was 5, repeat the completed sets.
6. If the exercise's primary muscle is a template focus muscle, add one set only when the current lift and the previous matching lift were both eligible for volume.
7. If the exercise's primary muscle is not a template focus muscle, add one set only when the current lift and the previous two matching lifts were all eligible for volume.
8. If volume is not added and every set is ready for load, add 5 lb to each set.
9. If load is not added, add one rep to each set, capped at the exercise's maximum hypertrophy reps.

## Volume Eligibility

A lift is eligible for volume when all of these are true:

- The lift was not skipped.
- Pain and effort feedback were submitted.
- Pain was 1 or 2.
- Effort was not above the target effort ceiling for that point in the program.
- Every completed working set reached at least the exercise's minimum hypertrophy reps.
- The lift has fewer than 5 working sets.

The target effort ceiling rises through the program:

- First 20% of the program: effort must be 1 or 2.
- Through 50% of the program: effort can be up to 3.
- After 50% of the program: effort can be up to 4.

## Weekly Muscle Set Cap

PowerJack does not add a volume set if the added set would push any credited muscle group above 25 sets in the previous program week.

The weekly cap uses the same set-credit model as training analytics:

- The exercise's primary muscle receives 1 set credit.
- Each secondary muscle receives 0.5 set credit.
- Secondary muscles that duplicate the primary muscle are ignored for the added-set projection.

For example, if Chest already has 25 set credits in the previous program week, a Chest-focused lift will not receive another set. The lift will continue to the load or rep progression rules instead. If a proposed added set would take a credited muscle exactly to 25, the extra set is allowed.

The cap is based on program weeks, not calendar weeks. When creating week 4, PowerJack checks completed set credits from program week 3.

## Load Progression

PowerJack adds load when all of these are true:

- The exercise is not reps-only.
- Every completed set reached at least 85% of the exercise's maximum hypertrophy reps, rounded up.
- Every completed set has a logged weight.
- The 5 lb increase is no more than 10% of each set's logged weight.

If any of those checks fail, PowerJack increases reps instead.

## Rep Progression

Rep progression adds one rep to each completed working set. Planned reps never go above the exercise's maximum hypertrophy reps. Reps-only exercises always use rep progression when volume is not added and no earlier hold rule applies.

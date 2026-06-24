---
name: pj-linear-lookup
description: Use when a PowerJack task starts from a Linear issue key such as PJ-31. Requires the invoking chat message to include exactly one PJ issue key, verifies the issue belongs to the Linear project named PowerJack, sets it to In Progress when appropriate, reviews the full issue contents, and then proceeds in /plan mode before implementation.
---

# PowerJack Linear Lookup

## Overview

Load one PowerJack Linear issue, claim it deliberately, and turn the issue contents into a decision-complete implementation plan before code changes.

## Required Workflow

Follow these steps in order. Do not skip status handling or issue review.

1. Confirm the invoking chat message includes exactly one issue key matching `PJ-\d+`, such as `PJ-31`.
   - If no issue key is present, or if multiple issue keys are present, pause and ask the user for the single issue key to use before calling Linear.
   - Use only the issue key from the same message that invoked `$pj-linear-lookup`.
2. Use Linear tools only for tracker work.
   - If Linear tools are unavailable or authentication is missing, pause and ask the user to connect Linear.
   - Do not use GitHub, local files, or memory as substitutes for the Linear issue lookup.
3. Find the Linear project named exactly `PowerJack`.
   - Retrieve the target issue by key.
   - Verify the issue belongs to the `PowerJack` project.
   - If the issue is not found, or belongs to a different project, pause and report the mismatch.
4. Resolve the issue status.
   - If the issue status is already exactly `In Progress`, pause and ask the user whether to continue before planning.
   - Otherwise list the issue team's statuses, find the status named exactly `In Progress`, and update the issue to that status.
   - If no exact `In Progress` status exists, pause and ask the user how to proceed.
5. Review the complete issue context available through Linear before planning:
   - Issue key and title/name.
   - Project, status, labels/tags, priority, assignee, cycle, and related metadata when present.
   - Full description.
   - Acceptance criteria or AC from the description and any clearly labeled issue/comment content.
   - Comments, attachments, or linked context exposed by the Linear tools.
6. Proceed as if the user invoked `/plan` for this issue.
   - Summarize the issue intent and acceptance criteria in your own words.
   - Inspect the repository with non-mutating commands to ground the plan in the current implementation.
   - Ask for user input more often than usual when issue intent, AC, scope, UX behavior, data shape, or implementation tradeoffs are ambiguous.
   - Produce a decision-complete implementation plan before making code changes.

## Planning Standards

The plan must include the issue key, what success means, important implementation areas, tests and QA, and explicit assumptions. If the issue touches UI, iOS, database, or architecture boundaries, include the relevant PowerJack standards and verification steps from `AGENTS.md`.

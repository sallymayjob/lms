#!/usr/bin/env python3
"""
RWR Group Slack LMS — Workflow ID Patcher
==========================================
When n8n imports workflows, it may assign new internal IDs different from
the IDs embedded in the workflow JSON files. This script:

1. Queries the n8n API to discover the actual IDs assigned to each workflow
2. Identifies which workflows have IDs that differ from expected
3. Updates the supervisor-router's executeWorkflow node parameters to use
   the actual assigned IDs

Usage:
    python3 scripts/update-workflow-ids.py
    python3 scripts/update-workflow-ids.py --dry-run
    python3 scripts/update-workflow-ids.py --n8n-url http://localhost:5678 --auth admin:password
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
from typing import Optional

import requests

# ─── Expected name → ID mapping ──────────────────────────────────────────────
# These are the IDs embedded in the workflow JSON files.
# The patcher compares actual assigned IDs against these.
NAME_TO_EXPECTED_ID: dict[str, str] = {
    "Agent 02 — Quiz Master":            "wpJOwdjIluP9n6Tu",
    "Agent 03 — Tutor":                  "e0yErInDqhfKbNls",
    "Agent 04 — Progress Tracker":       "z8j0WZhQCfsduOdi",
    "Agent 05 — Course Catalog":         "a5CatalogWrkflw01",
    "Agent 06 — Help":                   "a6HelpWorkflow001",
    "Agent 07 — Certification":          "TcY8C8malQ5SiTqZ",
    "Agent 08 — Enrollment Manager":     "BjxEx4DjqMwlkrU4",
    "Agent 09 — Gap Analyst (Gemini)":   "g5ZY673tbmDswpl4",
    "Agent 10 — Unenroll":               "a10UnEnrollAgent1",
    "Agent 11 — Proactive Nudge":        "a11NudgeAgent001",
    "Agent 12 — Reporting Agent":        "HpgyOs9wKZz2mAQd",
    "Agent 13 — Onboarding Agent":       "R8adLhGssCewBrKC",
    "Agent 14 — Google Sheets Backup":   "BackupToGSheets01",
    "Agent 15 — Assignment Intake":      "a15AssignmentIntake001",
    "Agent 16 — Lesson Edit Detector":   "a16LessonEditDetect",
    "Agent 17 — Gemini Re-Tester":       "a17GeminiRetester01",
    "Agent 18 — Lesson Publisher":       "a18LessonPublisher1",
}

SUPERVISOR_NAME = "Supervisor Router"


def get_auth_header(auth: str) -> dict[str, str]:
    """Build Basic Auth header from 'user:password' string."""
    encoded = base64.b64encode(auth.encode()).decode()
    return {"Authorization": f"Basic {encoded}"}


def get_all_workflows(n8n_url: str, headers: dict[str, str]) -> list[dict]:
    """Fetch all workflows from the n8n API."""
    url = f"{n8n_url}/api/v1/workflows"
    try:
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        return response.json().get("data", [])
    except requests.RequestException as e:
        print(f"ERROR: Failed to fetch workflows from {url}: {e}", file=sys.stderr)
        sys.exit(1)


def build_name_to_actual_id(workflows: list[dict]) -> dict[str, str]:
    """Build mapping of workflow name → actual assigned ID."""
    mapping: dict[str, str] = {}
    for wf in workflows:
        name = wf.get("name", "")
        wf_id = str(wf.get("id", ""))
        if name:
            mapping[name] = wf_id
    return mapping


def find_supervisor(workflows: list[dict]) -> Optional[dict]:
    """Find the supervisor router workflow."""
    for wf in workflows:
        name = wf.get("name", "")
        if "supervisor" in name.lower() or "router" in name.lower():
            return wf
    return None


def patch_execute_workflow_nodes(
    workflow_json: dict,
    name_to_actual: dict[str, str],
    dry_run: bool = False
) -> tuple[dict, int]:
    """
    Walk all nodes in the workflow and patch executeWorkflow node parameters
    to use actual assigned IDs instead of expected IDs.

    Returns: (patched_workflow_json, number_of_patches_applied)
    """
    patches = 0
    nodes = workflow_json.get("nodes", [])

    for node in nodes:
        if node.get("type") != "n8n-nodes-base.executeWorkflow":
            continue

        params = node.get("parameters", {})
        workflow_id_param = params.get("workflowId", {})

        current_id = None
        if isinstance(workflow_id_param, dict):
            current_id = workflow_id_param.get("value")
        elif isinstance(workflow_id_param, str):
            current_id = workflow_id_param

        if not current_id:
            continue

        # Find which workflow name matches this ID
        matched_name = None
        for name, expected_id in NAME_TO_EXPECTED_ID.items():
            if current_id == expected_id:
                matched_name = name
                break

        if not matched_name:
            continue

        actual_id = name_to_actual.get(matched_name)
        if not actual_id:
            print(f"  WARN: Could not find actual ID for '{matched_name}'")
            continue

        if actual_id == current_id:
            print(f"  OK: '{matched_name}' ID unchanged ({current_id})")
            continue

        print(f"  PATCH: '{matched_name}': {current_id} → {actual_id}")

        if not dry_run:
            if isinstance(workflow_id_param, dict):
                node["parameters"]["workflowId"]["value"] = actual_id
            else:
                node["parameters"]["workflowId"] = actual_id
            patches += 1
        else:
            patches += 1

    return workflow_json, patches


def update_workflow(
    n8n_url: str,
    headers: dict[str, str],
    workflow_id: str,
    workflow_data: dict
) -> bool:
    """Push the patched workflow back to n8n via PUT."""
    url = f"{n8n_url}/api/v1/workflows/{workflow_id}"
    try:
        response = requests.put(
            url,
            headers={**headers, "Content-Type": "application/json"},
            json=workflow_data,
            timeout=30
        )
        response.raise_for_status()
        return True
    except requests.RequestException as e:
        print(f"ERROR: Failed to update workflow {workflow_id}: {e}", file=sys.stderr)
        return False


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Patch n8n supervisor-router executeWorkflow node IDs"
    )
    parser.add_argument(
        "--n8n-url",
        default=os.environ.get("N8N_API_URL", "http://localhost:5678"),
        help="n8n base URL (default: http://localhost:5678)"
    )
    parser.add_argument(
        "--auth",
        default=f"{os.environ.get('N8N_BASIC_AUTH_USER', 'admin')}:{os.environ.get('N8N_BASIC_AUTH_PASSWORD', '')}",
        help="Basic auth in user:password format"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be patched without making any changes"
    )
    args = parser.parse_args()

    if args.dry_run:
        print("DRY RUN mode — no changes will be made")

    headers = get_auth_header(args.auth)

    # Step 1: Get all workflows and build name→ID mapping
    print("\n→ Fetching all workflows from n8n API...")
    workflows = get_all_workflows(args.n8n_url, headers)
    print(f"  Found {len(workflows)} workflow(s)")

    name_to_actual = build_name_to_actual_id(workflows)

    # Step 2: Compare actual IDs to expected IDs
    print("\n→ Comparing actual vs expected workflow IDs:")
    id_mismatches: dict[str, tuple[str, str]] = {}  # name → (expected, actual)

    for name, expected_id in NAME_TO_EXPECTED_ID.items():
        actual_id = name_to_actual.get(name)
        if not actual_id:
            print(f"  MISSING: '{name}' — not found in n8n (workflow not imported yet?)")
        elif actual_id != expected_id:
            print(f"  MISMATCH: '{name}': expected={expected_id}, actual={actual_id}")
            id_mismatches[name] = (expected_id, actual_id)
        else:
            print(f"  MATCH: '{name}' ({actual_id})")

    if not id_mismatches:
        print("\n✓ All workflow IDs match — no patching required")
        return

    # Step 3: Find the supervisor-router
    print(f"\n→ Locating supervisor router workflow...")
    supervisor = find_supervisor(workflows)
    if not supervisor:
        print("  WARN: Supervisor router not found. Patching skipped.", file=sys.stderr)
        return

    supervisor_id = str(supervisor["id"])
    supervisor_name = supervisor.get("name", "unknown")
    print(f"  Found: '{supervisor_name}' (ID: {supervisor_id})")

    # Step 4: Patch the supervisor router
    print(f"\n→ Patching executeWorkflow nodes in supervisor router:")
    patched_workflow, patches_count = patch_execute_workflow_nodes(
        workflow_json=supervisor,
        name_to_actual=name_to_actual,
        dry_run=args.dry_run
    )

    if patches_count == 0:
        print("  No executeWorkflow nodes needed patching")
        return

    print(f"\n  Applied {patches_count} patch(es)")

    # Step 5: Push patched workflow back to n8n
    if not args.dry_run:
        print(f"\n→ Updating supervisor router in n8n (ID: {supervisor_id})...")
        success = update_workflow(args.n8n_url, headers, supervisor_id, patched_workflow)
        if success:
            print(f"✓ Supervisor router updated successfully")
        else:
            print("✗ Failed to update supervisor router", file=sys.stderr)
            sys.exit(1)
    else:
        print("\n(DRY RUN: skipping API update)")


if __name__ == "__main__":
    main()

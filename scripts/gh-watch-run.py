#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import time


FAIL_CONCLUSIONS = {
    "failure",
    "cancelled",
    "timed_out",
    "startup_failure",
    "action_required",
}


def run_cmd(cmd, capture=True, check=True):
    if capture:
        result = subprocess.run(cmd, check=check, text=True, stdout=subprocess.PIPE)
        return result.stdout.strip()
    subprocess.run(cmd, check=check)
    return ""


def iso_now_utc():
    return dt.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"


def sanitize_filename(value):
    value = re.sub(r"[^\w.-]+", "_", value.strip())
    return value[:120] if value else "job"


def gh_args(repo):
    return ["--repo", repo] if repo else []


def wait_for_run_id(workflow, ref, repo, start_ts, poll):
    while True:
        runs_json = run_cmd(
            [
                "gh",
                "run",
                "list",
                "--workflow",
                workflow,
                "--branch",
                ref,
                "--json",
                "databaseId,createdAt,status,headSha",
                *gh_args(repo),
            ]
        )
        runs = json.loads(runs_json or "[]")
        for run in runs:
            if run.get("createdAt", "") >= start_ts:
                return run["databaseId"]
        time.sleep(poll)


def get_run(run_id, repo):
    run_json = run_cmd(
        [
            "gh",
            "run",
            "view",
            str(run_id),
            "--json",
            "status,conclusion,updatedAt,jobs",
            *gh_args(repo),
        ]
    )
    return json.loads(run_json)


def cancel_run(run_id, repo):
    run_cmd(["gh", "run", "cancel", str(run_id), *gh_args(repo)], capture=False)


def download_logs_and_artifacts(run_id, repo, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    run = get_run(run_id, repo)
    with open(os.path.join(out_dir, "run.json"), "w", encoding="utf-8") as handle:
        json.dump(run, handle, indent=2, sort_keys=True)

    jobs = run.get("jobs", [])
    for job in jobs:
        job_id = job.get("databaseId")
        job_name = sanitize_filename(job.get("name", "job"))
        if not job_id:
            continue
        log_path = os.path.join(out_dir, f"job-{job_id}-{job_name}.log")
        log_text = run_cmd(
            ["gh", "run", "view", str(run_id), "--log", "--job", str(job_id), *gh_args(repo)]
        )
        with open(log_path, "w", encoding="utf-8") as handle:
            handle.write(log_text)

    artifacts_dir = os.path.join(out_dir, "artifacts")
    os.makedirs(artifacts_dir, exist_ok=True)
    try:
        run_cmd(
            ["gh", "run", "download", str(run_id), "-D", artifacts_dir, *gh_args(repo)],
            capture=False,
        )
    except subprocess.CalledProcessError:
        pass


def main():
    parser = argparse.ArgumentParser(
        description="Trigger a GitHub Actions workflow run and monitor until completion."
    )
    parser.add_argument("--workflow", default="CI", help="Workflow name or file (default: CI)")
    parser.add_argument("--ref", help="Git ref/branch to run against (required if starting a run)")
    parser.add_argument("--repo", help="GitHub repo (owner/name)")
    parser.add_argument("--run-id", type=int, help="Existing run ID to monitor")
    parser.add_argument("--poll", type=int, default=10, help="Poll interval in seconds (default: 10)")
    parser.add_argument(
        "--output",
        default=os.path.join("logs", "gh-actions"),
        help="Directory to store logs/artifacts",
    )
    args = parser.parse_args()

    run_id = args.run_id
    if run_id is None:
        if not args.ref:
            print("--ref is required when --run-id is not provided", file=sys.stderr)
            return 2
        start_ts = iso_now_utc()
        run_cmd(
            ["gh", "workflow", "run", args.workflow, "-r", args.ref, *gh_args(args.repo)],
            capture=False,
        )
        run_id = wait_for_run_id(args.workflow, args.ref, args.repo, start_ts, args.poll)
        print(f"Started run {run_id}")

    failure_detected = False
    while True:
        run = get_run(run_id, args.repo)
        status = run.get("status")
        conclusion = run.get("conclusion")
        jobs = run.get("jobs", [])

        failed_jobs = [
            j for j in jobs if j.get("conclusion") in FAIL_CONCLUSIONS
        ]
        if failed_jobs and status != "completed":
            failure_detected = True
            print("Failure detected; cancelling run.")
            cancel_run(run_id, args.repo)

        if status == "completed":
            failure_detected = failure_detected or (conclusion in FAIL_CONCLUSIONS)
            break

        time.sleep(args.poll)

    out_dir = os.path.join(args.output, f"run-{run_id}")
    download_logs_and_artifacts(run_id, args.repo, out_dir)

    if failure_detected:
        print(f"Run {run_id} failed; logs/artifacts saved to {out_dir}")
        return 1
    print(f"Run {run_id} succeeded; logs/artifacts saved to {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

List all currently running and pending GitHub Actions workflow runs, then interactively cancel selected ones.

## Steps

1. Run two separate commands to get running and queued workflow runs (gh run list ignores multiple --status flags, so query each separately):
   ```
   gh run list --status in_progress --json databaseId,displayTitle,status,workflowName,createdAt,headBranch --limit 50
   gh run list --status queued --json databaseId,displayTitle,status,workflowName,createdAt,headBranch --limit 50
   ```
   Merge and deduplicate the results by databaseId before displaying.

2. Parse the JSON output and display a numbered list like:
   ```
   #  ID          Status       Workflow              Branch         Title                  Started
   1. 1234567890  in_progress  Build / docker-x86    main           ci: update deps        2026-03-26 10:05
   2. 9876543210  queued       Build / raspberrypi   fix/some-bug   fix: something         2026-03-26 10:07
   ```
   If no runs are found, say so and stop.

3. Ask the user: "Which runs do you want to cancel? Enter numbers separated by spaces (e.g. 1 3), or 'all' to cancel all, or 'none' to abort:"

4. Wait for the user's response. If they say 'none' or provide no valid selection, abort without cancelling anything.

5. For each selected run, cancel it with:
   ```
   gh run cancel <databaseId>
   ```
   Print the result of each cancellation (success or error).

6. Summarize how many runs were successfully cancelled.

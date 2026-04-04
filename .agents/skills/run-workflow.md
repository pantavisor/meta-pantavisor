List GitHub Actions workflows in `.github/workflows/`, let the user pick one, collect any required inputs, and trigger it on the current branch.

The user may invoke this skill with a hint in their message (e.g. "run test workflow", "run the pvtests workflow", "run docker build"). If a keyword hint is present, try to fuzzy-match it against workflow filenames and display names. If exactly one match is found, skip the selection list and go directly to step 4 with that workflow. If multiple matches or no matches are found, show the full list as normal.

## Steps

1. **Get the current branch:**
   ```
   git rev-parse --abbrev-ref HEAD
   ```

2. **List workflows** from `.github/workflows/` — only files with `workflow_dispatch:` triggers are runnable manually. Read each `.yaml` / `.yml` file and filter to those containing `workflow_dispatch`.

   If the user's message contained a keyword hint, fuzzy-match it against filenames and `name:` fields (case-insensitive, partial match). If exactly one workflow matches, skip straight to step 4 with that workflow — do not show the list.

   Otherwise display a numbered list:
   ```
   #  File                               Name
   1. manual-pvtests.yaml                MAN: start pvtests
   2. manual-scarthgap-docker-x86_64.yaml  MAN: docker-x86_64-scarthgap
   ...
   ```
   Extract the workflow `name:` field for the display name. If no runnable workflows found, say so and stop.

3. **Ask the user:** "Which workflow do you want to run? Enter the number:"

4. **Wait for selection (or use auto-matched workflow).** Read the chosen workflow file and parse the `on.workflow_dispatch.inputs` section. If there are no inputs, skip to step 7.

5. **Display the inputs** in a table:
   ```
   Input         Required  Type    Description
   test_type     YES       string  pvtests-local or pvtests-remote
   test_number   no        string  Test number to run (e.g., "0" for remote:0)
   ```
   If an input has a `default:` value, show it too.

6. **Ask for each input value** one at a time. For required inputs, re-prompt if left blank. For optional inputs, tell the user they can type `skip` or `no` to omit the value. If the user responds with `skip`, `no`, or any clear intent to skip, do not pass that input flag.

7. **Confirm and run** the workflow. Show the command before running it:
   ```
   gh workflow run <filename> --ref <current-branch> [-f key=value ...]
   ```
   Ask: "Run this? (y/n):" — proceed only on 'y'.

8. **Trigger the workflow:**
   ```
   gh workflow run <filename> --ref <current-branch> [-f key=value ...]
   ```
   Only pass `-f key=value` for inputs that have a non-empty value.

9. After triggering, wait ~3 seconds then fetch the run URL with:
   ```
   gh run list --workflow <filename> --limit 1 --json url,databaseId,status
   ```
   Print the run URL so the user can follow along in the browser.

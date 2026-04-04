Fetch the meta-pantavisor releases.json from S3, display releases and RC versions compactly, then optionally delete selected version entries from releases.json.

If the user just wants a quick summary (e.g. "list releases", "what versions are available"), skip to the summary step after downloading and print:
```
Stable: 026, 025, 024
RC:     027-rc5, 027-rc2, 027-rc1, 024-rc3, 024-rc2, 024-rc1
```
Then stop — do not show the full table or ask about deletion unless the user asks for it.

## Structure

The JSON has two top-level keys:
- `stable`: map of version → array of machine entries
- `release-candidate`: map of rc-version → array of machine entries

Each machine entry has: `name`, `full_image.url`, `pvrexports.url`, `bsp.url`.
The S3 prefix for a version is derived from the URL, e.g. `meta-pantavisor/026/`.

The user must have aws s3 credential authenticated on his computer.

## Steps

1. Create the local directory and download the file:
   ```
   mkdir -p /tmp/meta-pantavisor-ci
   aws s3 cp s3://pantavisor-ci/meta-pantavisor/releases.json /tmp/meta-pantavisor-ci/releases.json
   ```
   If the download fails, report the error and stop.

2. Parse the JSON and display a compact numbered table:
   ```
   Stable releases:
   #   Version     Machines
   1.  026         docker-x86_64-scarthgap, imx8qxp-b0-mek-scarthgap, ...
   2.  025         docker-x86_64-scarthgap, raspberrypi-armv8-scarthgap, ...
   3.  024         ...
   4.  02-test     ...

   Release candidates:
   #   Version     Machines
   5.  027-rc5     docker-x86_64-scarthgap, ...
   6.  027-rc2     ...
   7.  027-rc1     ...
   8.  024-rc3     ...
   9.  024-rc2     ...
   10. 024-rc1     ...
   11. 000-rc-test ...
   ```
   Sort stable releases newest-first, RC versions newest-first.
   List machine names inline, truncate with `...` if more than 4.

3. Ask the user: "Which versions do you want to delete? Enter numbers separated by spaces (e.g. 1 3), 'all' to delete all, or 'none' to abort:"

4. Wait for the user's response. If they say 'none' or provide no valid selection, abort without deleting anything.

5. For each selected version, remove its key from the local `/tmp/meta-pantavisor-ci/releases.json` using jq. Stable versions are under `.stable`, RC versions under `."release-candidate"`.

6. Upload the updated releases.json back to S3:
   ```
   aws s3 cp /tmp/meta-pantavisor-ci/releases.json s3://pantavisor-ci/meta-pantavisor/releases.json
   ```

7. Summarize how many versions were removed from releases.json and confirm the upload succeeded.

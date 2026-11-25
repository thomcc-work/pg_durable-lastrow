#!/usr/bin/env bash
# Run via scripts/check --cli-errors, in its own newly seeded cluster.
set -euo pipefail
app=$1 cluster=$2
expect_error() {
    local needle=$1 output
    shift
    if output=$("$@" 2>&1); then echo "Unexpected success: $output" >&2; exit 1; fi
    if [[ $output != *"$needle"* ]]; then
        printf 'Expected %s, got: %s\n' "$needle" "$output" >&2
        exit 1
    fi
}

id=$("$app" start)
"$app" verify "$id"
unrelated=$("$cluster" psql -qAtc "SELECT df.start('SELECT 1', 'not-the-backfill')")
expect_error "cannot attribute totals to $unrelated" "$app" verify "$unrelated"
"$app" verify "$id"  # An unrelated workflow must not invalidate the original.
second=$("$app" start)
expect_error "cannot attribute totals to $second" "$app" verify "$second"
expect_error "cannot attribute totals to $id" "$app" verify "$id"

"$cluster" psql -U postgres -qc 'REVOKE UPDATE (total_cents, update_count) ON lastrow.orders FROM lastrow_app'
bad=$("$app" start)
expect_error "permission denied for table orders" "$app" verify "$bad"
expect_error "permission denied for table orders" "$app" status "$bad"
echo 'Rejected wrong and duplicate runs; both commands surfaced the failed batch.'

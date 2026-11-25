# lastrow

Backfill 100 order totals while a customer holds a lock on order 17. A Rust
client submits the job to pg_durable and exits. The other 99 totals become
visible in batches of up to ten. Order 17 stays on the **same job's** to-do list
until the customer commits.

## Try it in two terminals

Use Bash, Rust/Cargo, and a local PostgreSQL installation with pg_durable
installed for the server selected by `pg_config`. Tested on PostgreSQL 17.11
with pg_durable 0.2.8 and 0.2.9. Run as a regular OS user.

For the automated version, run `./scripts/check` from the checkout (it uses
GNU `timeout`). It holds the lock until a committed batch actually updates
zero orders, checks the original ID after release, and removes its temporary
cluster on success. `./scripts/check --cli-errors` tests
wrong IDs, duplicate submissions, and failed SQL in a separate cluster.
To control the lock yourself:

**Terminal A**, from this checkout:

```bash
cargo build --locked --target-dir target
app=$PWD/target/debug/lastrow
cluster=$PWD/scripts/cluster
work=$(mktemp -d) &&
  cd -- "$work" &&
  "$cluster" init &&
  printf 'cd %q && %q psql\n' "$PWD" "$cluster"
```

`init` seeds a fresh, socket-only cluster in `.lastrow` in the current
directory. No system database or existing demo is reset. If setup fails,
`init` stops its own server and keeps the files for inspection. On success,
paste the printed command in **terminal B**, then take the lock in psql:

```sql
BEGIN;
SELECT id FROM lastrow.orders WHERE id = 17 FOR UPDATE;
```

Leave that transaction open. In **A**, launch once and save the ID:

```bash
id=$("$app" start)
"$app" status "$id"
```

Repeat **only the status command** until you see this combination:

```text
id=41e5697c state=running done=99/100 pending=[17] batch_rows=0 retry_timer=running
```

Your ID will differ. Seeing 99 alone is too early: `batch_rows=0` and the
running timer show that the worker already tried again and found nothing it
could lock. Now release the order in **B**:

```sql
COMMIT;
\q
```

In **A**, verify the original ID. This waits up to 60 seconds for the workflow
and then compares every total to its line items in a fresh query. The write
counters belong to the orders, so verification refuses to credit a run if you
launched a second backfill in the same demo.

```bash
"$app" verify "$id"
# id=41e5697c state=completed orders=100 correct_totals=100 written_once=100
"$cluster" stop
```

The stopped cluster stays in that temporary directory; remove it when you no
longer need the data. Start in a fresh directory for another demo.

## Why an empty batch isn't the end

The [workflow](sql/start.sql) locks up to ten orders with `NULL` totals using
`FOR UPDATE SKIP LOCKED`. The same statement sums their line items in integer
cents, increments the demo write counter, and returns the updated IDs. The
next iteration starts at the first unfinished order, not after the last ID it
processed.

No returned IDs means **nothing claimable**, not **nothing owed**. Only then
does an ordinary `EXISTS` read check for unfinished orders. If one remains,
`df.sleep(3)` schedules a durable retry; otherwise the loop ends. The cohort
and line items are fixed for this demo. It needs neither an external scheduler
nor a connected client between batches.

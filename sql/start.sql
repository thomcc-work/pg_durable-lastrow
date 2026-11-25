SELECT df.start(
    df.loop(
        $batch$
            WITH picked AS (
                SELECT id FROM lastrow.orders
                WHERE total_cents IS NULL
                ORDER BY id LIMIT 10
                FOR UPDATE SKIP LOCKED
            )
            UPDATE lastrow.orders AS o
            SET total_cents = (
                    SELECT sum(li.quantity::bigint * li.unit_cents)
                    FROM lastrow.line_items AS li WHERE li.order_id = o.id
                ),
                update_count = o.update_count + 1
            FROM picked WHERE o.id = picked.id
            RETURNING o.id
        $batch$ |=> 'batch'
        ~> df.if_rows(
            'batch',
            'SELECT 1', -- A productive batch needs no other work this iteration.
            df.if(
                'SELECT EXISTS (SELECT FROM lastrow.orders WHERE total_cents IS NULL)',
                df.sleep(3),
                df.break()
            )
        )
    ),
    'lastrow-totals'
)

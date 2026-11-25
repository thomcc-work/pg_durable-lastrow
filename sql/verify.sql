WITH expected AS (
    SELECT order_id, sum(quantity::bigint * unit_cents) AS cents
    FROM lastrow.line_items GROUP BY order_id
)
SELECT df.status($1) AS state, count(*) AS orders,
       count(*) FILTER (WHERE o.total_cents = e.cents) AS correct,
       count(*) FILTER (WHERE o.update_count = 1) AS written_once
FROM lastrow.orders AS o
LEFT JOIN expected AS e ON e.order_id = o.id

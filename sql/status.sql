WITH nodes AS (
    SELECT * FROM df.instance_nodes($1)
)
SELECT df.status($1) AS state,
       count(total_cents) AS done, count(*) AS orders,
       ARRAY(SELECT id FROM lastrow.orders WHERE total_cents IS NULL ORDER BY id) AS pending,
       (SELECT (result::jsonb ->> 'row_count')::integer FROM nodes
        WHERE result_name = 'batch' AND inferred_status = 'completed') AS batch_rows,
       EXISTS (SELECT FROM nodes WHERE node_type = 'SLEEP' AND inferred_status = 'running') AS retry_timer
FROM lastrow.orders

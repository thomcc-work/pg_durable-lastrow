SELECT coalesce(
    (SELECT output FROM df.instance_info($1)),
    (SELECT result::jsonb #>> '{}' FROM df.instance_nodes($1)
     WHERE inferred_status = 'failed' AND result IS NOT NULL
     ORDER BY (node_type = 'SQL') DESC, node_id LIMIT 1)
)

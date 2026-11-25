BEGIN;
CREATE EXTENSION pg_durable;
CREATE ROLE lastrow_app LOGIN;
SELECT df.grant_usage('lastrow_app');

CREATE SCHEMA lastrow;
CREATE TABLE lastrow.orders (
    id integer PRIMARY KEY CHECK (id BETWEEN 1 AND 100),
    total_cents bigint,
    update_count integer NOT NULL DEFAULT 0
);
CREATE TABLE lastrow.line_items (
    order_id integer NOT NULL REFERENCES lastrow.orders (id),
    line_no integer NOT NULL,
    quantity integer NOT NULL CHECK (quantity > 0),
    unit_cents integer NOT NULL CHECK (unit_cents >= 0),
    PRIMARY KEY (order_id, line_no)
);

INSERT INTO lastrow.orders (id) SELECT generate_series(1, 100);
INSERT INTO lastrow.line_items (order_id, line_no, quantity, unit_cents)
SELECT id, 1, 1 + id % 3, 125 + id FROM lastrow.orders
UNION ALL
SELECT id, 2, 2, 399 FROM lastrow.orders;

GRANT USAGE ON SCHEMA lastrow TO lastrow_app;
GRANT SELECT ON lastrow.orders, lastrow.line_items TO lastrow_app;
GRANT UPDATE (total_cents, update_count) ON lastrow.orders TO lastrow_app;
COMMIT;

SELECT current_setting('server_version') AS postgres, extversion AS pg_durable
FROM pg_extension WHERE extname = 'pg_durable';

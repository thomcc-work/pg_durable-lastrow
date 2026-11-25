-- Count actual updates, including empty statements. Use the top-level XID:
-- a row's xmin can identify a savepoint instead of the committing transaction.
CREATE TABLE lastrow.batch_probe (tx xid8 NOT NULL, written bigint NOT NULL);
GRANT INSERT, SELECT ON lastrow.batch_probe TO lastrow_app;

CREATE FUNCTION lastrow.observe_batch() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO lastrow.batch_probe
    SELECT pg_current_xact_id(), count(*) FROM changed;
    RETURN NULL;
END
$$;

CREATE TRIGGER observe_batch AFTER UPDATE ON lastrow.orders
REFERENCING NEW TABLE AS changed FOR EACH STATEMENT
EXECUTE FUNCTION lastrow.observe_batch();

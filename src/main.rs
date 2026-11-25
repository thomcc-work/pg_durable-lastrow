use postgres::{Client, Config, NoTls};
use std::{env, error::Error, process::ExitCode};

type Result<T> = std::result::Result<T, Box<dyn Error>>;
const USAGE: &str = "usage: lastrow start | status ID | verify ID";

fn connect() -> Result<Client> {
    Ok(Config::new()
        .host_path(env::current_dir()?.join(".lastrow"))
        .dbname("postgres")
        .user("lastrow_app")
        .application_name("lastrow")
        .connect(NoTls)?)
}

fn start(db: &mut Client) -> Result<()> {
    let mut tx = db.transaction()?;
    let id: String = tx
        .query_one(include_str!("../sql/start.sql"), &[])?
        .try_get(0)?;
    tx.commit()?;
    println!("{id}");
    Ok(())
}

fn check_outcome(db: &mut Client, id: &str, state: &str) -> Result<()> {
    if matches!(state, "failed" | "cancelled") {
        let row = db.query_one(include_str!("../sql/failure.sql"), &[&id])?;
        return Err(match row.try_get::<_, Option<&str>>(0)? {
            Some(detail) => format!("workflow {id} {state}: {detail}"),
            None => format!("workflow {id} {state}"),
        }
        .into());
    }
    Ok(())
}

fn status(db: &mut Client, id: &str) -> Result<()> {
    let row = db.query_one(include_str!("../sql/status.sql"), &[&id])?;
    let state = row
        .try_get::<_, Option<&str>>("state")?
        .ok_or_else(|| format!("no visible workflow with ID {id}"))?;
    let done: i64 = row.try_get("done")?;
    let orders: i64 = row.try_get("orders")?;
    let pending: Vec<i32> = row.try_get("pending")?;
    let batch: Option<i32> = row.try_get("batch_rows")?;
    let timer: bool = row.try_get("retry_timer")?;
    println!(
        "id={id} state={state} done={done}/{orders} pending={pending:?} batch_rows={} retry_timer={}",
        batch.map_or_else(|| "-".into(), |n| n.to_string()),
        if timer { "running" } else { "off" }
    );
    check_outcome(db, id, state)
}

fn verify(db: &mut Client, id: &str) -> Result<()> {
    let outcome = db.query_one("SELECT df.await_instance($1, 60)", &[&id])?;
    let state: &str = outcome.try_get(0)?;
    check_outcome(db, id, state)?;
    let row = db.query_one(include_str!("../sql/verify.sql"), &[&id])?;
    if !row.try_get::<_, bool>("sole_run")? {
        return Err(format!(
            "cannot attribute totals to {id}: verification requires that ID to be the only lastrow-totals run in this demo"
        )
        .into());
    }
    let orders: i64 = row.try_get("orders")?;
    let correct: i64 = row.try_get("correct")?;
    let once: i64 = row.try_get("written_once")?;
    println!("id={id} state={state} orders={orders} correct_totals={correct} written_once={once}");
    if state != "completed" || (orders, correct, once) != (100, 100, 100) {
        return Err("expected a completed workflow and 100 correct, singly written orders".into());
    }
    Ok(())
}

fn run() -> Result<()> {
    let args: Vec<_> = env::args().skip(1).collect();
    match args.as_slice() {
        [cmd] if cmd == "start" => start(&mut connect()?),
        [cmd, id] if cmd == "status" => status(&mut connect()?, id),
        [cmd, id] if cmd == "verify" => verify(&mut connect()?, id),
        [cmd] if cmd == "--help" || cmd == "-h" => {
            println!("{USAGE}");
            Ok(())
        }
        _ => Err(USAGE.into()),
    }
}

fn main() -> ExitCode {
    if let Err(err) = run() {
        eprintln!("lastrow: {err}");
        let mut cause = err.source();
        while let Some(e) = cause {
            eprintln!("  {e}");
            cause = e.source();
        }
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}

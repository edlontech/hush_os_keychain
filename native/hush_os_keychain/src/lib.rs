mod error;
mod platform;

use rustler::types::atom;
use rustler::{Encoder, Env, Term};

use crate::error::NifError;

#[rustler::nif(schedule = "DirtyIo")]
fn fetch(service: String, account: Option<String>) -> Result<String, NifError> {
    let store = platform::store()?;
    Ok(platform::lookup(&store, &service, account.as_deref())?.get_password()?)
}

#[rustler::nif(schedule = "DirtyIo")]
fn put(env: Env<'_>, service: String, account: String, secret: String) -> Term<'_> {
    let result = platform::store().and_then(|store| {
        platform::put(&store, &service, &account, &secret).map_err(NifError::from)
    });
    ok_or_error(env, result)
}

#[rustler::nif(schedule = "DirtyIo")]
fn delete(env: Env<'_>, service: String, account: Option<String>) -> Term<'_> {
    let result = platform::store().and_then(|store| {
        platform::delete(&store, &service, account.as_deref()).map_err(NifError::from)
    });
    ok_or_error(env, result)
}

fn ok_or_error(env: Env<'_>, result: Result<(), NifError>) -> Term<'_> {
    match result {
        Ok(()) => atom::ok().encode(env),
        Err(err) => (atom::error(), err).encode(env),
    }
}

rustler::init!("Elixir.HushOsKeychain.Native");

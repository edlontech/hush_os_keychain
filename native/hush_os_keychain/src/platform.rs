use std::collections::HashMap;
use std::sync::{Arc, Mutex, PoisonError};

use keyring_core::api::CredentialStore;
use keyring_core::{Entry, Error, Result};

use crate::error::NifError;

static STORE: Mutex<Option<Arc<CredentialStore>>> = Mutex::new(None);

pub fn store() -> std::result::Result<Arc<CredentialStore>, NifError> {
    let mut cached = STORE.lock().unwrap_or_else(PoisonError::into_inner);
    if let Some(store) = cached.as_ref() {
        return Ok(Arc::clone(store));
    }
    let created = os_store()?;
    *cached = Some(Arc::clone(&created));
    Ok(created)
}

#[cfg(target_os = "macos")]
fn os_store() -> std::result::Result<Arc<CredentialStore>, NifError> {
    let store =
        apple_native_keyring_store::keychain::Store::new().map_err(NifError::unavailable)?;
    Ok(store)
}

#[cfg(target_os = "windows")]
fn os_store() -> std::result::Result<Arc<CredentialStore>, NifError> {
    let store = windows_native_keyring_store::Store::new().map_err(NifError::unavailable)?;
    Ok(store)
}

#[cfg(all(unix, not(target_os = "macos")))]
fn os_store() -> std::result::Result<Arc<CredentialStore>, NifError> {
    let store = zbus_secret_service_keyring_store::Store::new().map_err(NifError::unavailable)?;
    Ok(store)
}

#[cfg(not(any(target_os = "macos", target_os = "windows", unix)))]
fn os_store() -> std::result::Result<Arc<CredentialStore>, NifError> {
    Err(NifError::Unavailable("unsupported platform".into()))
}

pub fn lookup(store: &Arc<CredentialStore>, service: &str, account: Option<&str>) -> Result<Entry> {
    #[cfg(target_os = "windows")]
    {
        let target = HashMap::from([("target", service)]);
        let entry = store.build(service, account.unwrap_or(""), Some(&target))?;
        if let Some(acct) = account
            && entry.get_attributes()?.get("username").map(String::as_str) != Some(acct)
        {
            return Err(Error::NoEntry);
        }
        Ok(entry)
    }
    #[cfg(not(target_os = "windows"))]
    match account {
        Some(acct) => store.build(service, acct, None),
        None => {
            let mut found = store.search(&HashMap::from([("service", service)]))?;
            match found.len() {
                0 => Err(Error::NoEntry),
                1 => Ok(found.remove(0)),
                _ => Err(Error::Ambiguous(found)),
            }
        }
    }
}

pub fn put(store: &Arc<CredentialStore>, service: &str, account: &str, secret: &str) -> Result<()> {
    #[cfg(target_os = "windows")]
    {
        let entry = store.build(
            service,
            account,
            Some(&HashMap::from([("target", service)])),
        )?;
        entry.set_password(secret)?;
        entry.update_attributes(&HashMap::from([("username", account)]))
    }
    #[cfg(all(unix, not(target_os = "macos")))]
    {
        let entry = store.build(service, account, Some(&HashMap::from([("label", service)])))?;
        entry.set_password(secret)
    }
    #[cfg(not(any(target_os = "windows", all(unix, not(target_os = "macos")))))]
    {
        store.build(service, account, None)?.set_password(secret)
    }
}

pub fn delete(store: &Arc<CredentialStore>, service: &str, account: Option<&str>) -> Result<()> {
    lookup(store, service, account)?.delete_credential()
}

#[cfg(all(test, not(target_os = "windows")))]
mod tests {
    use super::*;

    fn sample_store() -> Arc<CredentialStore> {
        keyring_core::sample::Store::new().unwrap()
    }

    #[test]
    fn lookup_without_account_and_no_match_is_no_entry() {
        let store = sample_store();
        assert!(matches!(lookup(&store, "svc", None), Err(Error::NoEntry)));
    }

    #[test]
    fn lookup_without_account_and_one_match_returns_it() {
        let store = sample_store();
        store
            .build("svc", "alice", None)
            .unwrap()
            .set_password("pw")
            .unwrap();
        let entry = lookup(&store, "svc", None).unwrap();
        assert_eq!(entry.get_password().unwrap(), "pw");
    }

    #[test]
    fn lookup_without_account_and_two_matches_is_ambiguous() {
        let store = sample_store();
        store
            .build("svc", "alice", None)
            .unwrap()
            .set_password("a")
            .unwrap();
        store
            .build("svc", "bob", None)
            .unwrap()
            .set_password("b")
            .unwrap();
        assert!(matches!(lookup(&store, "svc", None), Err(Error::Ambiguous(v)) if v.len() == 2));
    }

    #[test]
    fn lookup_with_account_picks_that_account() {
        let store = sample_store();
        store
            .build("svc", "alice", None)
            .unwrap()
            .set_password("a")
            .unwrap();
        store
            .build("svc", "bob", None)
            .unwrap()
            .set_password("b")
            .unwrap();
        let entry = lookup(&store, "svc", Some("bob")).unwrap();
        assert_eq!(entry.get_password().unwrap(), "b");
        let missing = lookup(&store, "svc", Some("carol")).unwrap();
        assert!(matches!(missing.get_password(), Err(Error::NoEntry)));
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn put_then_delete_round_trips_through_lookup() {
        let store = sample_store();
        put(&store, "svc", "alice", "pw").unwrap();
        assert_eq!(
            lookup(&store, "svc", Some("alice"))
                .unwrap()
                .get_password()
                .unwrap(),
            "pw"
        );
        delete(&store, "svc", None).unwrap();
        assert!(matches!(lookup(&store, "svc", None), Err(Error::NoEntry)));
    }
}

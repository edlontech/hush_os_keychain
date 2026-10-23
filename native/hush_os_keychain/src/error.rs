use rustler::{Encoder, Env, Term};

mod atoms {
    rustler::atoms! {
        not_found,
        unavailable,
        ambiguous,
        access_denied,
        invalid,
        platform,
    }
}

#[derive(Debug)]
pub enum NifError {
    NotFound,
    Unavailable(String),
    Ambiguous(usize),
    AccessDenied(String),
    Invalid(String),
    Platform(String),
}

impl From<keyring_core::Error> for NifError {
    fn from(err: keyring_core::Error) -> Self {
        use keyring_core::Error::*;
        match err {
            NoEntry => NifError::NotFound,
            NoDefaultStore => NifError::Unavailable("no credential store".into()),
            NoStorageAccess(e) => NifError::AccessDenied(e.to_string()),
            Ambiguous(v) => NifError::Ambiguous(v.len()),
            BadEncoding(_) | BadDataFormat(_, _) => {
                NifError::Invalid("stored value is not UTF-8 text".into())
            }
            Invalid(p, why) => NifError::Invalid(format!("{p}: {why}")),
            TooLong(attr, limit) => NifError::Invalid(format!("{attr} exceeds {limit}")),
            PlatformFailure(e) => NifError::Platform(e.to_string()),
            BadStoreFormat(s) | NotSupportedByStore(s) => NifError::Platform(s),
            _ => NifError::Platform("unexpected keyring error".into()),
        }
    }
}

impl NifError {
    pub fn unavailable(err: keyring_core::Error) -> Self {
        match NifError::from(err) {
            NifError::Unavailable(msg)
            | NifError::AccessDenied(msg)
            | NifError::Invalid(msg)
            | NifError::Platform(msg) => NifError::Unavailable(msg),
            NifError::NotFound | NifError::Ambiguous(_) => {
                NifError::Unavailable("credential store could not be created".into())
            }
        }
    }
}

impl Encoder for NifError {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        match self {
            NifError::NotFound => atoms::not_found().encode(env),
            NifError::Unavailable(msg) => (atoms::unavailable(), msg).encode(env),
            NifError::Ambiguous(n) => (atoms::ambiguous(), n).encode(env),
            NifError::AccessDenied(msg) => (atoms::access_denied(), msg).encode(env),
            NifError::Invalid(msg) => (atoms::invalid(), msg).encode(env),
            NifError::Platform(msg) => (atoms::platform(), msg).encode(env),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bad_encoding_maps_to_invalid_without_the_secret() {
        let err = NifError::from(keyring_core::Error::BadEncoding(b"s3cret".to_vec()));
        match err {
            NifError::Invalid(msg) => assert!(!msg.contains("s3cret")),
            other => panic!("expected Invalid, got {other:?}"),
        }
    }
}

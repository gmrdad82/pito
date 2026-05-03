//! Serde adapter for booleans that cross the JSON boundary as the strings
//! `"yes"` / `"no"`.
//!
//! Internal Rust types stay `bool` for type safety; this module bridges to and
//! from the wire format expected by the Pito Rails API. Apply with
//! `#[serde(with = "crate::api::yes_no")]` for `bool` fields, or
//! `#[serde(with = "crate::api::yes_no::option")]` for `Option<bool>`.

use serde::{Deserialize, Deserializer, Serializer};

pub fn deserialize<'de, D>(deserializer: D) -> Result<bool, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    match s.as_str() {
        "yes" => Ok(true),
        "no" => Ok(false),
        other => Err(serde::de::Error::custom(format!(
            "expected \"yes\" or \"no\", got {other:?}"
        ))),
    }
}

pub fn serialize<S>(value: &bool, serializer: S) -> Result<S::Ok, S::Error>
where
    S: Serializer,
{
    serializer.serialize_str(if *value { "yes" } else { "no" })
}

/// Convenience adapter for `Option<bool>` fields. `None` round-trips through
/// JSON `null`; `Some(true)` / `Some(false)` map to `"yes"` / `"no"`.
#[allow(dead_code)]
pub mod option {
    use super::*;

    pub fn deserialize<'de, D>(deserializer: D) -> Result<Option<bool>, D::Error>
    where
        D: Deserializer<'de>,
    {
        let opt: Option<String> = Option::deserialize(deserializer)?;
        match opt.as_deref() {
            None => Ok(None),
            Some("yes") => Ok(Some(true)),
            Some("no") => Ok(Some(false)),
            Some(other) => Err(serde::de::Error::custom(format!(
                "expected \"yes\" or \"no\", got {other:?}"
            ))),
        }
    }

    pub fn serialize<S>(value: &Option<bool>, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        match value {
            Some(b) => serializer.serialize_str(if *b { "yes" } else { "no" }),
            None => serializer.serialize_none(),
        }
    }
}

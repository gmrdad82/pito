//! HTTP client wrappers for the Rails footages JSON API. The `models` module
//! holds the wire types (probed file, footage record, request/response shapes);
//! `client` holds the actual GET/POST/PATCH/DELETE calls.

pub mod client;
pub mod models;

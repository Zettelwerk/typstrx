//! Fetches and caches the `@preview` package index for `@`-completions
//! (`typst_ide::IdeWorld::packages`).

use std::sync::{Arc, OnceLock};

use ecow::EcoString;
use typst_kit::downloader::{Downloader, SystemDownloader};
use typst_syntax::package::PackageSpec;

const INDEX_URL: &str = "https://packages.typst.org/preview/index.json";

/// Shared, lazily-populated cache of every published `@preview` package
/// version.
///
/// `World::packages` returns `&[...]` borrowed from `&self`, with no room
/// for I/O — so this can only ever be populated once, in the background.
/// [`Self::spawn_fetch`] starts that; a caller who asks (via
/// [`Self::packages`]) before it lands just sees an empty list, same as if
/// package completions weren't implemented at all. In practice the fetch (a
/// few hundred milliseconds for the whole index) finishes well before a
/// user gets to typing `@` in a fresh session.
///
/// Deliberately not refreshable after that: making it so would need either
/// unsafe code or leaking the old `Vec` on every refresh, for a list that's
/// only ever consulted for autocompletion (staleness of a few hours is a
/// non-issue there).
#[derive(Clone, Default)]
pub struct PackageIndex(Arc<OnceLock<Vec<(PackageSpec, Option<EcoString>)>>>);

impl PackageIndex {
    /// Every known package version, most-recently-fetched — or empty if the
    /// background fetch hasn't landed (or was never started).
    pub fn packages(&self) -> &[(PackageSpec, Option<EcoString>)] {
        self.0.get().map(Vec::as_slice).unwrap_or(&[])
    }

    /// Starts a background fetch of the index, unless this index is already
    /// populated (repeated calls are safe — only the first does anything).
    /// Silently does nothing on failure (network down, bad JSON, ...):
    /// package completions just stay empty, same as before this existed.
    pub fn spawn_fetch(&self, user_agent: impl Into<EcoString>) {
        if self.0.get().is_some() {
            return;
        }
        let cache = self.0.clone();
        let user_agent = user_agent.into();
        std::thread::spawn(move || {
            if let Some(packages) = fetch(&user_agent) {
                // A racing fetch may have already won; either result is
                // equally valid, so just drop ours rather than error.
                let _ = cache.set(packages);
            }
        });
    }

    /// Pre-fills this index synchronously, bypassing the network — for
    /// tests that need deterministic package completions.
    #[cfg(test)]
    pub fn for_testing(packages: Vec<(PackageSpec, Option<EcoString>)>) -> Self {
        let cell = OnceLock::new();
        let _ = cell.set(packages);
        Self(Arc::new(cell))
    }
}

fn fetch(user_agent: &str) -> Option<Vec<(PackageSpec, Option<EcoString>)>> {
    // Reuses `typst-kit`'s own HTTPS client (system-native TLS, proxy-aware,
    // same one package *downloads* already go through) rather than adding a
    // second HTTP stack just for this.
    let downloader = SystemDownloader::new(user_agent);
    let body = downloader.download(&(), INDEX_URL).ok()?;
    let entries: Vec<serde_json::Value> = serde_json::from_slice(&body).ok()?;
    Some(entries.iter().filter_map(parse_entry).collect())
}

/// Parses one `index.json` entry. Every version of every package is its own
/// entry there (not just the latest) — `typst_ide::complete::package_completions`
/// already dedups to the newest version per package itself, so all of them
/// are passed through here unfiltered.
fn parse_entry(entry: &serde_json::Value) -> Option<(PackageSpec, Option<EcoString>)> {
    let name = entry.get("name")?.as_str()?;
    let version = entry.get("version")?.as_str()?.parse().ok()?;
    let description = entry.get("description").and_then(|d| d.as_str()).map(EcoString::from);
    let spec = PackageSpec { namespace: "preview".into(), name: name.into(), version };
    Some((spec, description))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_realistic_index_entries() {
        let json = serde_json::json!([
            {"name": "cetz", "version": "0.3.1", "description": "Draw diagrams.", "entrypoint": "lib.typ"},
            {"name": "cetz", "version": "0.2.0", "description": "An older cetz.", "entrypoint": "lib.typ"},
            {"name": "no-description", "version": "1.0.0", "entrypoint": "lib.typ"},
            {"name": "malformed"},
        ]);
        let entries: Vec<_> = json.as_array().unwrap().iter().filter_map(parse_entry).collect();

        // The malformed entry (missing `version`) is skipped, not fatal to
        // the rest of the fetch.
        assert_eq!(entries.len(), 3);

        let (spec, desc) = &entries[0];
        assert_eq!(spec.namespace, "preview");
        assert_eq!(spec.name, "cetz");
        assert_eq!(spec.version.to_string(), "0.3.1");
        assert_eq!(desc.as_deref(), Some("Draw diagrams."));

        assert_eq!(entries[2].1, None, "a missing description must become None, not an empty string");
    }
}

//! The [`typst::World`] implementation backing a [`crate::api::session::TypstSession`].

use std::collections::HashMap;

use ecow::EcoString;
use parking_lot::Mutex;
use typst::diag::{FileError, FileResult};
use typst::foundations::{Bytes, Datetime, Duration};
use typst::syntax::{FileId, RootedPath, Source, VirtualPath, VirtualRoot};
use typst::text::{Font, FontBook};
use typst::utils::LazyHash;
use typst::{Library, LibraryExt, World};
use typst_kit::datetime::Time;
use typst_kit::downloader::SystemDownloader;
use typst_kit::files::{FileLoader, FileStore};
use typst_kit::fonts::FontStore;
use typst_kit::packages::{FsPackages, SystemPackages, UniversePackages};

use crate::packages::{PackageEntry, PackageIndex};

/// The virtual path under which the main source is registered.
const MAIN_PATH: &str = "/main.typ";

/// User agent reported to the package registry when downloading packages.
const USER_AGENT: &str = concat!("typstrx/", env!("CARGO_PKG_VERSION"));

/// Configuration for creating a [`TypstrxWorld`].
pub struct WorldOptions {
    /// Directory where downloaded `@preview` packages are cached. When `None`,
    /// the platform's standard Typst cache directory is used.
    pub package_cache_dir: Option<String>,
    /// Whether `@preview` packages may be downloaded from the network.
    pub allow_package_download: bool,
}

/// An in-memory Typst world.
///
/// The main source and any additional project files live in memory; package
/// files come from the package cache directory (downloaded on demand).
pub struct TypstrxWorld {
    library: LazyHash<Library>,
    fonts: FontStore,
    files: FileStore<InMemoryLoader>,
    main: FileId,
    time: Time,
    /// Backs [`typst_ide::IdeWorld::packages`], for `@`-completions. See
    /// [`PackageIndex`] for why it's fetched once in the background rather
    /// than refreshed.
    package_index: PackageIndex,
}

impl TypstrxWorld {
    pub fn new(options: WorldOptions) -> Self {
        let mut fonts = FontStore::new();
        fonts.extend(typst_kit::fonts::embedded());

        let cache = match options.package_cache_dir {
            Some(dir) => Some(FsPackages::new(dir)),
            None => FsPackages::system_cache(),
        };
        let universe = if options.allow_package_download {
            UniversePackages::new(SystemDownloader::new(USER_AGENT))
        } else {
            UniversePackages::new(DisabledDownloader {})
        };
        let packages = SystemPackages::from_parts(FsPackages::system_data(), cache, universe);

        let package_index = PackageIndex::default();
        if options.allow_package_download {
            package_index.spawn_fetch(USER_AGENT);
        }

        let main = RootedPath::new(
            VirtualRoot::Project,
            VirtualPath::new(MAIN_PATH).expect("main path is valid"),
        )
        .intern();

        let mut world = Self {
            library: LazyHash::new(Library::default()),
            fonts,
            files: FileStore::new(InMemoryLoader {
                files: Mutex::new(HashMap::new()),
                packages,
            }),
            main,
            time: Time::system(),
            package_index,
        };
        world.set_main_source("");
        world
    }

    /// Replaces the main source text and prepares for the next compilation.
    pub fn set_main_source(&mut self, text: &str) {
        self.files
            .loader()
            .files
            .lock()
            .insert(self.main, Bytes::from_string(text.to_string()));
        self.reset();
    }

    /// Adds or replaces an in-memory project file (e.g. an image or a module
    /// imported by the main source).
    pub fn set_file(&mut self, path: &str, data: Vec<u8>) -> Result<(), EcoString> {
        let vpath = VirtualPath::new(path).map_err(|err| EcoString::from(err.to_string()))?;
        let id = RootedPath::new(VirtualRoot::Project, vpath).intern();
        if id == self.main {
            return Err("cannot overwrite the main source via set_file".into());
        }
        self.files
            .loader()
            .files
            .lock()
            .insert(id, Bytes::new(data));
        self.reset();
        Ok(())
    }

    /// Registers all font faces contained in `data`. Returns how many faces
    /// were added.
    pub fn register_font(&mut self, data: Vec<u8>) -> u32 {
        let mut count = 0;
        for font in Font::iter(Bytes::new(data)) {
            let info = font.info().clone();
            self.fonts.push((font, info));
            count += 1;
        }
        count
    }

    /// Marks cached files as stale and refreshes the compilation clock; call
    /// before every compilation so file edits are picked up while sources are
    /// still updated in place (which preserves incremental performance).
    fn reset(&mut self) {
        self.files.reset();
        self.time.reset();
    }

    /// Replaces [`Self::package_index`] with a synchronously pre-filled one
    /// (see [`PackageIndex::for_testing`]) — for deterministic package
    /// completion tests, bypassing the network entirely.
    #[cfg(test)]
    pub fn set_packages_for_testing(&mut self, packages: Vec<PackageEntry>) {
        self.package_index = PackageIndex::for_testing(packages);
    }
}

impl typst_ide::IdeWorld for TypstrxWorld {
    fn upcast(&self) -> &dyn World {
        self
    }

    fn packages(&self) -> &[PackageEntry] {
        self.package_index.packages()
    }
}

impl World for TypstrxWorld {
    fn library(&self) -> &LazyHash<Library> {
        &self.library
    }

    fn book(&self) -> &LazyHash<FontBook> {
        self.fonts.book()
    }

    fn main(&self) -> FileId {
        self.main
    }

    fn source(&self, id: FileId) -> FileResult<Source> {
        self.files.source(id)
    }

    fn file(&self, id: FileId) -> FileResult<Bytes> {
        self.files.file(id)
    }

    fn font(&self, index: usize) -> Option<Font> {
        self.fonts.font(index)
    }

    fn today(&self, offset: Option<Duration>) -> Option<Datetime> {
        self.time.today(offset)
    }
}

/// Serves project files from memory and package files via [`SystemPackages`].
struct InMemoryLoader {
    files: Mutex<HashMap<FileId, Bytes>>,
    packages: SystemPackages,
}

impl FileLoader for InMemoryLoader {
    fn load(&self, id: FileId) -> FileResult<Bytes> {
        match id.root() {
            VirtualRoot::Project => {
                self.files.lock().get(&id).cloned().ok_or_else(|| {
                    FileError::NotFound(id.vpath().get_with_slash().to_string().into())
                })
            }
            VirtualRoot::Package(spec) => self.packages.obtain(spec)?.load(id.vpath()),
        }
    }
}

/// A downloader that rejects every request; used when package downloads are
/// disabled so cached packages still work.
struct DisabledDownloader {}

impl typst_kit::downloader::Downloader for DisabledDownloader {
    fn stream(
        &self,
        _key: &dyn std::any::Any,
        _url: &str,
    ) -> std::io::Result<(Option<usize>, Box<dyn std::io::Read>)> {
        Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "package downloads are disabled for this session",
        ))
    }
}

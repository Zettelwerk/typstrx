//! Plain data types that cross the FFI bridge by value.

/// Configuration for creating a Typst session.
pub struct SessionOptions {
    /// Directory where downloaded `@preview` packages are cached. When `None`,
    /// the platform's standard Typst cache directory is used (which may not be
    /// writable on mobile platforms — pass an app-specific directory there).
    pub package_cache_dir: Option<String>,
    /// Whether `@preview` packages may be downloaded from the network. Cached
    /// packages keep working when this is `false`.
    pub allow_package_download: bool,
}

impl Default for SessionOptions {
    fn default() -> Self {
        Self {
            package_cache_dir: None,
            allow_package_download: true,
        }
    }
}

/// The outcome of a compilation. Returned for both successful and failed
/// compiles; `success` tells them apart and `diagnostics` carries errors and
/// warnings in both cases.
pub struct CompileResult {
    /// Identifies the compiled document. Subsequent render/text calls must
    /// pass this value and fail with [`TypstrxError::Stale`] once a newer
    /// compilation has completed.
    pub generation: u64,
    /// Whether a document was produced. On failure the previous document (if
    /// any) stays available under its own generation.
    pub success: bool,
    /// Per-page sizes of the compiled document. Empty on failure.
    pub pages: Vec<PageInfo>,
    /// Errors and warnings emitted by the compiler.
    pub diagnostics: Vec<TypstDiagnostic>,
    /// Wall-clock compilation time in milliseconds.
    pub elapsed_ms: u64,
}

/// Size of a single page in typographic points (1/72 inch).
pub struct PageInfo {
    pub width_pt: f64,
    pub height_pt: f64,
}

/// Severity of a [`TypstDiagnostic`].
pub enum DiagnosticSeverity {
    Error,
    Warning,
}

/// A compiler error or warning.
///
/// Source positions are only resolved for spans that point into the main
/// source (not into packages or other files) and are `None` otherwise.
/// `utf16_start`/`utf16_end` index the main source as a Dart `String`.
pub struct TypstDiagnostic {
    pub severity: DiagnosticSeverity,
    pub message: String,
    pub hints: Vec<String>,
    /// Start offset into the main source in UTF-16 code units.
    pub utf16_start: Option<u32>,
    /// End offset into the main source in UTF-16 code units.
    pub utf16_end: Option<u32>,
    /// 1-based line of the start offset.
    pub line: Option<u32>,
    /// 1-based column (in UTF-16 code units) of the start offset.
    pub column: Option<u32>,
}

/// A rendered tile of a page: straight RGBA8888 pixels, `width * height * 4`
/// bytes, rows top-to-bottom.
pub struct RenderedRegion {
    pub width: u32,
    pub height: u32,
    pub pixels: Vec<u8>,
}

/// Errors reported by session calls.
#[derive(Debug)]
pub enum TypstrxError {
    /// The passed generation no longer identifies the latest compiled
    /// document. The caller should drop the request silently.
    Stale,
    /// No document has been compiled successfully yet.
    NoDocument,
    /// The page index is out of bounds for the compiled document.
    PageOutOfRange { page_count: u32 },
    /// The requested render exceeds the pixel budget.
    RenderTooLarge { message: String },
    /// Any other failure, e.g. an invalid virtual file path.
    Other { message: String },
}

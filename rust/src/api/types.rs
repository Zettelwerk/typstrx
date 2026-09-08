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

/// One node of a syntax-highlighting tree for Typst source.
///
/// Mirrors the shape of the parse tree: a node with `children` is a grouping
/// construct (e.g. strong emphasis, a heading) and its own `text` is empty; a
/// node with no children is a leaf and `text` is its literal source text.
/// Concatenating every leaf's `text` in tree order reproduces the exact
/// source that was highlighted, so offsets never need to cross the bridge —
/// a caller can track them by summing leaf text lengths while walking.
pub struct HighlightNode {
    /// The highlighting category, if any. `None` for plain/ungrouped nodes.
    pub tag: Option<HighlightTag>,
    /// This node's literal text, non-empty only for leaves.
    pub text: String,
    /// Child nodes, non-empty only for non-leaves.
    pub children: Vec<HighlightNode>,
}

/// A syntax-highlighting category, mirroring `typst_syntax::Tag`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HighlightTag {
    Comment,
    Punctuation,
    Escape,
    Strong,
    Emph,
    Link,
    Raw,
    Label,
    Ref,
    Heading,
    ListMarker,
    ListTerm,
    MathDelimiter,
    MathOperator,
    MathGroupingParens,
    Keyword,
    Operator,
    Number,
    String,
    Function,
    Interpolated,
    Error,
}

/// The result of computing completions at a cursor position.
///
/// Completions are analyzed against the source as of the last `compile()`
/// call (successful or not) — value-aware completions (e.g. field access)
/// need the World's own registered `Source` to resolve, which only reflects
/// edits once they have gone through `compile()`. `generation` identifies
/// that state: compare it against the `generation` of the document
/// currently displayed (from the last successful `compile()`) and discard
/// the result if they don't match, rather than applying `apply_from_utf16`
/// against a buffer it wasn't computed for.
pub struct CompletionResult {
    /// The generation this analysis ran against.
    pub generation: u64,
    /// Where the completions apply from, in UTF-16 code units. Applying a
    /// completion means replacing the source range from this offset to the
    /// cursor with the chosen [`TypstCompletion::apply`].
    pub apply_from_utf16: u32,
    pub completions: Vec<TypstCompletion>,
}

/// The result of computing a hover tooltip. See [`CompletionResult`] for
/// what `generation` means and why it's needed.
pub struct HoverResult {
    pub generation: u64,
    pub tooltip: Option<TypstTooltip>,
}

/// An autocompletion option.
pub struct TypstCompletion {
    pub kind: TypstCompletionKind,
    /// The text shown in the completion list.
    pub label: String,
    /// The text to insert, already defaulted to `label` when Typst didn't
    /// supply one. May contain snippet placeholders like `${name}` or an
    /// empty tab stop `${}`; there is no numbering — stops are visited in
    /// the order they appear in the string.
    pub apply: String,
    /// An optional one-sentence description.
    pub detail: Option<String>,
}

/// A kind of item that can be completed, mirroring `typst_ide::CompletionKind`.
pub enum TypstCompletionKind {
    Syntax,
    Func,
    Type,
    Param,
    Constant,
    Path,
    Package,
    Label,
    Font,
    /// A symbol (e.g. a math shorthand). `notation` is its literal
    /// shorthand/name, not user-facing text.
    Symbol { notation: String },
}

/// A hover tooltip, mirroring `typst_ide::Tooltip`.
#[derive(Debug)]
pub enum TypstTooltip {
    /// Plain text.
    Text { content: String },
    /// A string of Typst code, e.g. a function signature — callers may want
    /// to render this in a monospace/code style.
    Code { content: String },
}

/// A rectangle in page coordinates: typographic points, top-left origin,
/// y-down (`top <= bottom`).
#[derive(Clone, Debug, PartialEq)]
pub struct RectPt {
    pub left: f64,
    pub top: f64,
    pub right: f64,
    pub bottom: f64,
}

/// Text and link geometry of one page.
pub struct PageTextData {
    /// The page's text in visual reading order, lines separated by `\n`.
    pub full_text: String,
    /// One rect per UTF-16 code unit of `full_text` (so the list indexes the
    /// text as a Dart `String`). Newline separators have zero-width rects.
    pub char_rects: Vec<RectPt>,
    /// Consecutive runs of `full_text` with their bounds; fragments cover the
    /// whole text without gaps.
    pub fragments: Vec<TextFragmentData>,
    /// Links on the page.
    pub links: Vec<LinkData>,
}

/// A text run: `full_text[index..index + length]` (UTF-16 indices).
pub struct TextFragmentData {
    pub index: u32,
    pub length: u32,
    pub bounds: RectPt,
}

/// A link region on a page. Either `url` or the `dest_*` fields are set.
pub struct LinkData {
    pub rect: RectPt,
    /// External URL, if this is a web link.
    pub url: Option<String>,
    /// Target page (1-based) for an internal link.
    pub dest_page: Option<u32>,
    /// Target x position on the destination page in points.
    pub dest_x_pt: Option<f64>,
    /// Target y position on the destination page in points.
    pub dest_y_pt: Option<f64>,
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

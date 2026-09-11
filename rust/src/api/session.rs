//! The Typst compilation session exposed to Dart.

use std::time::Instant;

use flutter_rust_bridge::frb;
use parking_lot::RwLock;
use typst::diag::{Severity, SourceDiagnostic};
use typst::ecow::EcoVec;
use typst::{World, WorldExt};
use typst_layout::PagedDocument;

use crate::api::types::{
    CompileResult, CompletionResult, DiagnosticSeverity, FunctionInfoResult, HighlightNode,
    HoverResult, PageInfo, PageTextData, RenderedRegion, SessionOptions, TypstDiagnostic,
    TypstFoldingRange, TypstrxError,
};
use crate::render::render_region;
use crate::world::{TypstrxWorld, WorldOptions};

/// A Typst compilation session.
///
/// Owns a [`TypstrxWorld`] that is kept alive across compilations so Typst's
/// built-in incremental compilation (comemo memoization) stays effective.
/// Compilations take the write lock; rendering and text extraction take read
/// locks and can run concurrently.
#[frb(opaque)]
pub struct TypstSession {
    inner: RwLock<SessionInner>,
}

struct SessionInner {
    world: TypstrxWorld,
    /// Monotonically increasing id, bumped on every successful compile.
    generation: u64,
    compiled: Option<Compiled>,
}

struct Compiled {
    generation: u64,
    document: PagedDocument,
}

impl TypstSession {
    /// Creates a new session. Fonts embedded in the library are available
    /// immediately; additional fonts can be added with [`register_font`].
    pub fn create(options: SessionOptions) -> TypstSession {
        TypstSession {
            inner: RwLock::new(SessionInner {
                world: TypstrxWorld::new(WorldOptions {
                    package_cache_dir: options.package_cache_dir,
                    allow_package_download: options.allow_package_download,
                }),
                generation: 0,
                compiled: None,
            }),
        }
    }

    /// Compiles `source` as the main file.
    ///
    /// On success the result carries a new generation and the page sizes; on
    /// failure the previous document (if any) remains valid and renderable.
    /// Diagnostics (errors and warnings) are always included.
    pub fn compile(&self, source: String) -> CompileResult {
        let mut inner = self.inner.write();
        let start = Instant::now();

        inner.world.set_main_source(&source);
        let warned = typst::compile::<PagedDocument>(&inner.world);
        // Bound comemo's memoization memory, like typst-cli does per compile.
        comemo::evict(10);

        let mut diagnostics = map_diagnostics(&inner.world, &warned.warnings);
        let elapsed_ms = start.elapsed().as_millis() as u64;

        match warned.output {
            Ok(document) => {
                inner.generation += 1;
                let pages = document
                    .pages()
                    .iter()
                    .map(|page| PageInfo {
                        width_pt: page.frame.width().to_pt(),
                        height_pt: page.frame.height().to_pt(),
                    })
                    .collect();
                let generation = inner.generation;
                inner.compiled = Some(Compiled {
                    generation,
                    document,
                });
                CompileResult {
                    generation,
                    success: true,
                    pages,
                    diagnostics,
                    elapsed_ms,
                }
            }
            Err(errors) => {
                diagnostics.extend(map_diagnostics(&inner.world, &errors));
                CompileResult {
                    generation: inner.compiled.as_ref().map_or(0, |c| c.generation),
                    success: false,
                    pages: Vec::new(),
                    diagnostics,
                    elapsed_ms,
                }
            }
        }
    }

    /// Computes a syntax-highlighting tree for `source`.
    ///
    /// Independent of compilation: this only parses, so it touches neither
    /// the session's lock nor its incremental-compile state, and cannot
    /// contend with an in-flight compile or render. Safe to call on every
    /// keystroke.
    pub fn highlight(&self, source: String) -> HighlightNode {
        crate::highlight::highlight_source(&source)
    }

    /// Computes folding ranges for `source` — collapsible regions like code
    /// blocks, content blocks, argument lists, array/dict literals, and
    /// block comments that span more than one line. See
    /// [`crate::folding`] for why headings aren't included.
    ///
    /// Independent of compilation, like [`Self::highlight`]. Unlike
    /// [`Self::completions`]/[`Self::hover`], there is no `generation` to
    /// check: the result is computed directly from `source`, not the
    /// World's own registered one, so it's already current for whatever the
    /// caller passes.
    pub fn folding_ranges(&self, source: String) -> Vec<TypstFoldingRange> {
        crate::folding::folding_ranges(&source)
    }

    /// Computes completions at `cursor_utf16` in the source as of the last
    /// `compile()` call (successful or not). See [`CompletionResult`] for
    /// why it isn't computed against whatever the caller's live buffer
    /// currently holds, and how to detect when the two have diverged.
    pub fn completions(&self, cursor_utf16: u32, explicit: bool) -> CompletionResult {
        let inner = self.inner.read();
        let generation = inner.generation;
        let doc = inner.compiled.as_ref().map(|c| &c.document);
        let Ok(source) = inner.world.source(inner.world.main()) else {
            return CompletionResult {
                generation,
                apply_from_utf16: cursor_utf16,
                completions: Vec::new(),
            };
        };
        let (apply_from_utf16, completions) =
            crate::completion::complete(&inner.world, doc, &source, cursor_utf16, explicit);
        CompletionResult {
            generation,
            apply_from_utf16,
            completions,
        }
    }

    /// Computes a hover tooltip at `cursor_utf16` in the source as of the
    /// last `compile()` call. See [`CompletionResult`] for what `generation`
    /// means and why this doesn't use the caller's live buffer directly.
    pub fn hover(&self, cursor_utf16: u32) -> HoverResult {
        let inner = self.inner.read();
        let generation = inner.generation;
        let doc = inner.compiled.as_ref().map(|c| &c.document);
        let Ok(source) = inner.world.source(inner.world.main()) else {
            return HoverResult {
                generation,
                tooltip: None,
            };
        };
        let tooltip = crate::completion::hover(&inner.world, doc, &source, cursor_utf16);
        HoverResult {
            generation,
            tooltip,
        }
    }

    /// Looks up documentation for the function named `label`, for an
    /// IntelliSense-style details panel shown alongside the completion list.
    ///
    /// `cursor_utf16` is used first, to resolve whatever's actually at that
    /// position in the source as of the last `compile()` call (handles field
    /// access like `calc.abs`, local functions, etc.); if that doesn't
    /// resolve to a function, falls back to a plain lookup of `label` in the
    /// global scope (handles browsing completions before a full expression
    /// exists, e.g. `#re|`). See [`CompletionResult`] for what `generation`
    /// means.
    pub fn function_info(&self, cursor_utf16: u32, label: String) -> FunctionInfoResult {
        let inner = self.inner.read();
        let generation = inner.generation;
        let Ok(source) = inner.world.source(inner.world.main()) else {
            return FunctionInfoResult { generation, info: None };
        };
        let info =
            crate::completion::function_info(&inner.world, &source, cursor_utf16, &label);
        FunctionInfoResult { generation, info }
    }

    /// Renders the window `(x, y, width, height)` in pixels out of page
    /// `page_index` (0-based) rasterized at a virtual full size of
    /// `full_width` × `full_height` pixels.
    ///
    /// Fails with [`TypstrxError::Stale`] when `generation` no longer matches
    /// the latest compiled document; callers should drop the request then.
    #[allow(clippy::too_many_arguments)] // deliberate region-API shape
    pub fn render_page_region(
        &self,
        generation: u64,
        page_index: u32,
        x: u32,
        y: u32,
        width: u32,
        height: u32,
        full_width: u32,
        full_height: u32,
        background_argb: u32,
    ) -> Result<RenderedRegion, TypstrxError> {
        let inner = self.inner.read();
        let compiled = inner.compiled.as_ref().ok_or(TypstrxError::NoDocument)?;
        if compiled.generation != generation {
            return Err(TypstrxError::Stale);
        }
        let pages = compiled.document.pages();
        let page = pages
            .get(page_index as usize)
            .ok_or(TypstrxError::PageOutOfRange {
                page_count: pages.len() as u32,
            })?;
        render_region(
            page,
            x,
            y,
            width,
            height,
            full_width,
            full_height,
            background_argb,
        )
    }

    /// Runs `f` with page `page_index` of the latest compiled document.
    ///
    /// Crate-internal, and deliberately not part of the Dart-facing API: the
    /// render tests need a `Page` to compare the clipped renderer against
    /// upstream whole-page rendering.
    #[cfg(test)]
    pub(crate) fn with_page<R>(
        &self,
        page_index: usize,
        f: impl FnOnce(&typst_layout::Page) -> R,
    ) -> Option<R> {
        let inner = self.inner.read();
        let compiled = inner.compiled.as_ref()?;
        compiled.document.pages().get(page_index).map(f)
    }

    /// Extracts text and link geometry for page `page_index` (0-based).
    ///
    /// Fails with [`TypstrxError::Stale`] when `generation` no longer matches
    /// the latest compiled document.
    pub fn page_text(
        &self,
        generation: u64,
        page_index: u32,
    ) -> Result<PageTextData, TypstrxError> {
        let inner = self.inner.read();
        let compiled = inner.compiled.as_ref().ok_or(TypstrxError::NoDocument)?;
        if compiled.generation != generation {
            return Err(TypstrxError::Stale);
        }
        let page_count = compiled.document.pages().len() as u32;
        if page_index >= page_count {
            return Err(TypstrxError::PageOutOfRange { page_count });
        }
        Ok(crate::text::extract_page_text(
            &compiled.document,
            page_index as usize,
        ))
    }

    /// Registers all font faces contained in `data` (TTF/OTF, also
    /// collections). Returns the number of faces added. Takes effect on the
    /// next compilation.
    pub fn register_font(&self, data: Vec<u8>) -> u32 {
        self.inner.write().world.register_font(data)
    }

    /// Adds or replaces an in-memory project file (image, bibliography,
    /// module, …) that the main source can reference by `path`.
    pub fn set_file(&self, path: String, data: Vec<u8>) -> Result<(), TypstrxError> {
        self.inner
            .write()
            .world
            .set_file(&path, data)
            .map_err(|message| TypstrxError::Other {
                message: message.to_string(),
            })
    }
}

/// Converts compiler diagnostics, resolving source positions for spans that
/// point into the main source. Offsets are UTF-16 code units so they can index
/// the source as a Dart `String` directly.
fn map_diagnostics(
    world: &TypstrxWorld,
    diagnostics: &EcoVec<SourceDiagnostic>,
) -> Vec<TypstDiagnostic> {
    diagnostics
        .iter()
        .map(|diag| {
            let mut mapped = TypstDiagnostic {
                severity: match diag.severity {
                    Severity::Error => DiagnosticSeverity::Error,
                    Severity::Warning => DiagnosticSeverity::Warning,
                },
                message: diag.message.to_string(),
                hints: diag.hints.iter().map(|hint| hint.v.to_string()).collect(),
                utf16_start: None,
                utf16_end: None,
                line: None,
                column: None,
            };
            if diag.span.id() == Some(world.main()) {
                if let (Some(range), Ok(source)) =
                    (world.range(diag.span), world.source(world.main()))
                {
                    let lines = source.lines();
                    mapped.utf16_start = lines.byte_to_utf16(range.start).map(|v| v as u32);
                    mapped.utf16_end = lines.byte_to_utf16(range.end).map(|v| v as u32);
                    if let Some(line) = lines.byte_to_line(range.start) {
                        mapped.line = Some(line as u32 + 1);
                        mapped.column = lines
                            .line_to_byte(line)
                            .and_then(|line_start| lines.byte_to_utf16(line_start))
                            .zip(mapped.utf16_start)
                            .map(|(line_start, start)| start - line_start as u32);
                    }
                }
            }
            mapped
        })
        .collect()
}

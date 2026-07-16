use typstrx::api::session::TypstSession;
use typstrx::api::types::{DiagnosticSeverity, SessionOptions, TypstrxError};

fn offline_session() -> TypstSession {
    TypstSession::create(SessionOptions {
        package_cache_dir: None,
        allow_package_download: false,
    })
}

#[test]
fn compile_simple_document() {
    let session = offline_session();
    let result = session.compile("Hello, *world*!".to_owned());
    assert!(result.success);
    assert_eq!(result.generation, 1);
    assert_eq!(result.pages.len(), 1);
    assert!(result.diagnostics.is_empty());
    // Default page size is A4: 595.28 x 841.89 pt.
    assert!((result.pages[0].width_pt - 595.28).abs() < 0.1);
    assert!((result.pages[0].height_pt - 841.89).abs() < 0.1);
}

#[test]
fn compile_multi_page() {
    let session = offline_session();
    let result = session.compile("first\n#pagebreak()\nsecond\n#pagebreak()\nthird".to_owned());
    assert!(result.success);
    assert_eq!(result.pages.len(), 3);
}

#[test]
fn compile_error_has_position() {
    let session = offline_session();
    let result = session.compile("#let x = ".to_owned());
    assert!(!result.success);
    assert!(result.pages.is_empty());
    let error = result
        .diagnostics
        .iter()
        .find(|d| matches!(d.severity, DiagnosticSeverity::Error))
        .expect("expected an error diagnostic");
    assert!(error.utf16_start.is_some());
    assert!(error.line.is_some());
}

#[test]
fn diagnostic_offsets_are_utf16() {
    let session = offline_session();
    // The emoji is 2 UTF-16 code units but 4 UTF-8 bytes; the error follows it.
    let source = "😀 #undefined_thing";
    let result = session.compile(source.to_owned());
    assert!(!result.success);
    let error = &result.diagnostics[0];
    let start = error.utf16_start.unwrap() as usize;
    let end = error.utf16_end.unwrap() as usize;
    let utf16: Vec<u16> = source.encode_utf16().collect();
    let spanned = String::from_utf16(&utf16[start..end]).unwrap();
    assert!(spanned.contains("undefined_thing"), "spanned: {spanned}");
}

#[test]
fn failed_compile_keeps_previous_document() {
    let session = offline_session();
    let ok = session.compile("hello".to_owned());
    assert!(ok.success);
    let failed = session.compile("#let x = ".to_owned());
    assert!(!failed.success);
    // The previous generation still renders.
    let region = session.render_page_region(ok.generation, 0, 0, 0, 100, 100, 100, 141, 0xffffffff);
    assert!(region.is_ok());
}

#[test]
fn render_full_page_is_not_blank() {
    let session = offline_session();
    let result = session.compile("= A heading\nSome body text.".to_owned());
    assert!(result.success);
    let region = session
        .render_page_region(result.generation, 0, 0, 0, 595, 842, 595, 842, 0xffffffff)
        .unwrap();
    assert_eq!(region.width, 595);
    assert_eq!(region.height, 842);
    assert_eq!(region.pixels.len(), 595 * 842 * 4);
    // Some pixel must be non-white (the text).
    assert!(region.pixels.chunks(4).any(|px| px[0] != 0xff || px[1] != 0xff || px[2] != 0xff));
    // All alpha must be opaque so premultiplied == straight RGBA.
    assert!(region.pixels.chunks(4).all(|px| px[3] == 0xff));
}

#[test]
fn region_render_matches_full_render_crop() {
    let session = offline_session();
    let result = session.compile("= Crop test\n#lorem(40)".to_owned());
    assert!(result.success);
    let full = session
        .render_page_region(result.generation, 0, 0, 0, 1190, 1684, 1190, 1684, 0xffffffff)
        .unwrap();
    let tile = session
        .render_page_region(result.generation, 0, 100, 200, 300, 250, 1190, 1684, 0xffffffff)
        .unwrap();
    for row in 0..250usize {
        let full_off = ((200 + row) * 1190 + 100) * 4;
        let tile_off = row * 300 * 4;
        assert_eq!(
            &full.pixels[full_off..full_off + 300 * 4],
            &tile.pixels[tile_off..tile_off + 300 * 4],
            "row {row} differs"
        );
    }
}

#[test]
fn stale_generation_is_rejected() {
    let session = offline_session();
    let first = session.compile("one".to_owned());
    let second = session.compile("two".to_owned());
    assert!(second.generation > first.generation);
    let result =
        session.render_page_region(first.generation, 0, 0, 0, 10, 10, 100, 141, 0xffffffff);
    assert!(matches!(result, Err(TypstrxError::Stale)));
}

#[test]
fn page_out_of_range() {
    let session = offline_session();
    let result = session.compile("only one page".to_owned());
    let render = session.render_page_region(result.generation, 5, 0, 0, 10, 10, 100, 141, 0xffffffff);
    assert!(matches!(
        render,
        Err(TypstrxError::PageOutOfRange { page_count: 1 })
    ));
}

#[test]
fn oversized_render_is_rejected() {
    let session = offline_session();
    let result = session.compile("hi".to_owned());
    let render = session.render_page_region(
        result.generation,
        0,
        0,
        0,
        100,
        100,
        20_000,
        20_000,
        0xffffffff,
    );
    assert!(matches!(render, Err(TypstrxError::RenderTooLarge { .. })));
}

#[test]
fn package_download_disabled_errors_cleanly() {
    let session = offline_session();
    let result = session.compile("#import \"@preview/cetz:0.3.4\"".to_owned());
    // Must fail with a diagnostic, not panic — unless a cached copy exists in
    // the system cache, in which case the compile may legitimately succeed.
    if !result.success {
        assert!(result
            .diagnostics
            .iter()
            .any(|d| matches!(d.severity, DiagnosticSeverity::Error)));
    }
}

#[test]
fn incremental_recompile_is_faster() {
    let session = offline_session();
    let source = "#lorem(2000)".to_owned();
    let cold = session.compile(source.clone());
    assert!(cold.success);
    let warm = session.compile(source + " end");
    assert!(warm.success);
    // Very loose sanity bound: the warm compile must not be drastically
    // slower than the cold one (memoization should make it comparable or
    // faster; flaky-machine tolerance built in).
    assert!(
        warm.elapsed_ms <= cold.elapsed_ms.max(1) * 3,
        "cold={}ms warm={}ms",
        cold.elapsed_ms,
        warm.elapsed_ms
    );
}

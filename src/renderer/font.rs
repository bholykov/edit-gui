//! Font loading and glyph rasterization.

use fontdue::{Font, FontSettings};
use std::collections::HashMap;

/// Metrics for a rasterized glyph.
#[derive(Debug, Clone, Copy)]
pub struct GlyphMetrics {
    /// Width of the glyph in pixels
    pub width: usize,
    /// Height of the glyph in pixels
    pub height: usize,
    /// Horizontal offset from origin
    pub xmin: i32,
    /// Vertical offset from origin
    pub ymin: i32,
    /// Horizontal advance width
    pub advance_width: f32,
}

/// Rasterized glyph data.
pub struct RasterizedGlyph {
    /// Glyph metrics
    pub metrics: GlyphMetrics,
    /// Coverage bitmap (0-255, where 255 = full coverage)
    pub bitmap: Vec<u8>,
}

/// Manages font loading and glyph rasterization.
pub struct FontManager {
    font: Font,
    font_size: f32,
    /// Cache of rasterized glyphs: char -> RasterizedGlyph
    glyph_cache: HashMap<char, RasterizedGlyph>,
}

impl FontManager {
    /// Creates a new font manager with a default monospace font.
    pub fn new() -> Self {
        Self::with_font_size(14.0)
    }

    /// Creates a new font manager with a specific font size.
    pub fn with_font_size(font_size: f32) -> Self {
        let font_data = Self::load_system_font();
        let font = Font::from_bytes(font_data.as_slice(), FontSettings::default())
            .expect("Failed to load font");

        Self {
            font,
            font_size,
            glyph_cache: HashMap::new(),
        }
    }

    /// Loads a system monospace font.
    fn load_system_font() -> Vec<u8> {
        // Try to load SF Mono on macOS
        #[cfg(target_os = "macos")]
        {
            let font_paths = [
                "/System/Library/Fonts/SFNSMono.ttf",
                "/Library/Fonts/SF-Mono-Regular.otf",
                "/System/Library/Fonts/Monaco.dfont",
                "/System/Library/Fonts/Menlo.ttc",
            ];

            for path in &font_paths {
                if let Ok(data) = std::fs::read(path) {
                    return data;
                }
            }
        }

        // Fallback for other platforms or if no system font found
        panic!("No suitable monospace font found. Please install a monospace font.");
    }

    /// Rasterizes a glyph and returns the bitmap.
    pub fn rasterize_glyph(&mut self, ch: char) -> &RasterizedGlyph {
        self.glyph_cache.entry(ch).or_insert_with(|| {
            let (metrics, bitmap) = self.font.rasterize(ch, self.font_size);

            RasterizedGlyph {
                metrics: GlyphMetrics {
                    width: metrics.width,
                    height: metrics.height,
                    xmin: metrics.xmin,
                    ymin: metrics.ymin,
                    advance_width: metrics.advance_width,
                },
                bitmap,
            }
        })
    }

    /// Returns the metrics for a glyph without rasterizing.
    pub fn get_metrics(&mut self, ch: char) -> GlyphMetrics {
        self.rasterize_glyph(ch).metrics
    }

    /// Returns the font's line height.
    pub fn line_height(&self) -> f32 {
        self.font.horizontal_line_metrics(self.font_size)
            .map(|m| m.new_line_size)
            .unwrap_or(self.font_size * 1.2)
    }

    /// Returns the cell size (width and height) for monospace rendering.
    pub fn cell_size(&mut self) -> (f32, f32) {
        // Use 'M' as the reference character for monospace width
        let metrics = self.get_metrics('M');
        let width = metrics.advance_width;
        let height = self.line_height();
        (width, height)
    }

    /// Clears the glyph cache.
    pub fn clear_cache(&mut self) {
        self.glyph_cache.clear();
    }
}

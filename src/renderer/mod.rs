//! GPU renderer for Edit's framebuffer cells.
//!
//! This module provides GPU-accelerated rendering of terminal cells
//! using wgpu (Metal backend on macOS).

mod font;
mod atlas;
mod pipeline;

pub use font::{FontManager, GlyphMetrics};
pub use atlas::TextAtlas;
pub use pipeline::RenderPipeline;

use crate::framebuffer::FramebufferCell;
use crate::helpers::Size;

/// Main renderer that orchestrates font loading, atlas management, and GPU rendering.
pub struct Renderer {
    font_manager: FontManager,
    atlas: TextAtlas,
    pipeline: RenderPipeline,
}

impl Renderer {
    /// Creates a new renderer with the given wgpu device and queue.
    pub fn new(
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        surface_format: wgpu::TextureFormat,
        window_size: Size,
    ) -> Self {
        let font_manager = FontManager::new();
        let atlas = TextAtlas::new(device, 2048, 2048);
        let pipeline = RenderPipeline::new(device, surface_format, &atlas);

        Self {
            font_manager,
            atlas,
            pipeline,
        }
    }

    /// Renders the given cells to the target texture.
    pub fn render(
        &mut self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        target: &wgpu::TextureView,
        cells: impl Iterator<Item = FramebufferCell>,
        window_size: Size,
    ) {
        // TODO: Implement rendering
        // 1. Iterate through cells
        // 2. Rasterize glyphs not in atlas
        // 3. Update atlas texture
        // 4. Build vertex buffers
        // 5. Issue draw calls
    }

    /// Updates the window size.
    pub fn resize(&mut self, new_size: Size) {
        // TODO: Update projection matrix, etc.
    }
}

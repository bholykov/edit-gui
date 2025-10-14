//! Dynamic texture atlas for glyph caching.

use std::collections::HashMap;

/// Represents a region in the atlas texture.
#[derive(Debug, Clone, Copy)]
pub struct AtlasRegion {
    /// X coordinate in the atlas (pixels)
    pub x: u32,
    /// Y coordinate in the atlas (pixels)
    pub y: u32,
    /// Width in pixels
    pub width: u32,
    /// Height in pixels
    pub height: u32,
    /// Normalized texture coordinates (0.0 - 1.0)
    pub uv_min: [f32; 2],
    pub uv_max: [f32; 2],
}

/// Dynamic texture atlas for caching rasterized glyphs.
pub struct TextAtlas {
    /// The GPU texture
    texture: wgpu::Texture,
    /// Texture view for rendering
    texture_view: wgpu::TextureView,
    /// Bind group for shaders
    bind_group: Option<wgpu::BindGroup>,
    /// Atlas dimensions
    width: u32,
    height: u32,
    /// Current packing position (simple linear allocator for now)
    current_x: u32,
    current_y: u32,
    row_height: u32,
    /// Map of char -> atlas region
    glyph_map: HashMap<char, AtlasRegion>,
}

impl TextAtlas {
    /// Creates a new text atlas with the given dimensions.
    pub fn new(device: &wgpu::Device, width: u32, height: u32) -> Self {
        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("Text Atlas"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::R8Unorm, // Single-channel for coverage
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });

        let texture_view = texture.create_view(&wgpu::TextureViewDescriptor::default());

        Self {
            texture,
            texture_view,
            bind_group: None,
            width,
            height,
            current_x: 0,
            current_y: 0,
            row_height: 0,
            glyph_map: HashMap::new(),
        }
    }

    /// Adds a glyph to the atlas and returns its region.
    /// Returns None if the atlas is full.
    pub fn add_glyph(
        &mut self,
        queue: &wgpu::Queue,
        ch: char,
        glyph_width: u32,
        glyph_height: u32,
        bitmap: &[u8],
    ) -> Option<AtlasRegion> {
        // Check if glyph is already in atlas
        if let Some(region) = self.glyph_map.get(&ch) {
            return Some(*region);
        }

        // Simple row-based packing algorithm
        // Check if we need to move to next row
        if self.current_x + glyph_width > self.width {
            self.current_x = 0;
            self.current_y += self.row_height;
            self.row_height = 0;
        }

        // Check if we have vertical space
        if self.current_y + glyph_height > self.height {
            // Atlas is full - in a real implementation, we'd expand or evict old glyphs
            return None;
        }

        let x = self.current_x;
        let y = self.current_y;

        // Upload glyph bitmap to GPU
        queue.write_texture(
            wgpu::ImageCopyTexture {
                texture: &self.texture,
                mip_level: 0,
                origin: wgpu::Origin3d { x, y, z: 0 },
                aspect: wgpu::TextureAspect::All,
            },
            bitmap,
            wgpu::ImageDataLayout {
                offset: 0,
                bytes_per_row: Some(glyph_width),
                rows_per_image: Some(glyph_height),
            },
            wgpu::Extent3d {
                width: glyph_width,
                height: glyph_height,
                depth_or_array_layers: 1,
            },
        );

        // Calculate UV coordinates
        let uv_min = [
            x as f32 / self.width as f32,
            y as f32 / self.height as f32,
        ];
        let uv_max = [
            (x + glyph_width) as f32 / self.width as f32,
            (y + glyph_height) as f32 / self.height as f32,
        ];

        let region = AtlasRegion {
            x,
            y,
            width: glyph_width,
            height: glyph_height,
            uv_min,
            uv_max,
        };

        // Update packing state
        self.current_x += glyph_width;
        self.row_height = self.row_height.max(glyph_height);

        // Cache the region
        self.glyph_map.insert(ch, region);

        Some(region)
    }

    /// Gets the atlas region for a glyph if it exists.
    pub fn get_glyph(&self, ch: char) -> Option<AtlasRegion> {
        self.glyph_map.get(&ch).copied()
    }

    /// Returns the texture view for binding in shaders.
    pub fn texture_view(&self) -> &wgpu::TextureView {
        &self.texture_view
    }

    /// Sets the bind group for this atlas.
    pub fn set_bind_group(&mut self, bind_group: wgpu::BindGroup) {
        self.bind_group = Some(bind_group);
    }

    /// Gets the bind group for this atlas.
    pub fn bind_group(&self) -> Option<&wgpu::BindGroup> {
        self.bind_group.as_ref()
    }

    /// Clears the atlas.
    pub fn clear(&mut self) {
        self.current_x = 0;
        self.current_y = 0;
        self.row_height = 0;
        self.glyph_map.clear();
    }
}

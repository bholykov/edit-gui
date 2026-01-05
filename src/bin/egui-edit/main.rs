// Simple cross-platform text editor using egui
// Clean, minimal, functional

use eframe::egui;
use std::path::PathBuf;

fn main() -> eframe::Result {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([1024.0, 768.0])
            .with_title("Edit"),
        ..Default::default()
    };

    eframe::run_native(
        "Edit",
        options,
        Box::new(|_cc| Ok(Box::new(EditApp::default()))),
    )
}

struct EditApp {
    text: String,
    current_file: Option<PathBuf>,
    status_message: String,
    modified: bool,
}

impl Default for EditApp {
    fn default() -> Self {
        Self {
            text: "Welcome to Edit!\n\nStart typing or open a file...".to_string(),
            current_file: None,
            status_message: String::new(),
            modified: false,
        }
    }
}

impl eframe::App for EditApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Top menu bar
        egui::TopBottomPanel::top("menu_bar").show(ctx, |ui| {
            egui::menu::bar(ui, |ui| {
                ui.menu_button("File", |ui| {
                    if ui.button("New (Ctrl+N)").clicked() {
                        self.new_file();
                        ui.close_menu();
                    }
                    if ui.button("Open... (Ctrl+O)").clicked() {
                        self.open_file();
                        ui.close_menu();
                    }
                    if ui.button("Save (Ctrl+S)").clicked() {
                        self.save_file();
                        ui.close_menu();
                    }
                    if ui.button("Save As... (Ctrl+Shift+S)").clicked() {
                        self.save_file_as();
                        ui.close_menu();
                    }
                    ui.separator();
                    if ui.button("Quit (Ctrl+Q)").clicked() {
                        ctx.send_viewport_cmd(egui::ViewportCommand::Close);
                    }
                });
            });
        });

        // Status bar at bottom
        egui::TopBottomPanel::bottom("status_bar").show(ctx, |ui| {
            ui.horizontal(|ui| {
                let filename = self
                    .current_file
                    .as_ref()
                    .and_then(|p| p.file_name())
                    .and_then(|n| n.to_str())
                    .unwrap_or("Untitled");

                let modified_marker = if self.modified { " *" } else { "" };

                // Count lines and get cursor position (approximate)
                let lines = self.text.lines().count();

                ui.label(format!("{}{} | {} lines", filename, modified_marker, lines));

                if !self.status_message.is_empty() {
                    ui.separator();
                    ui.label(&self.status_message);
                }
            });
        });

        // Keyboard shortcuts
        if ctx.input(|i| i.modifiers.ctrl && i.key_pressed(egui::Key::N)) {
            self.new_file();
        }
        if ctx.input(|i| i.modifiers.ctrl && i.key_pressed(egui::Key::O)) {
            self.open_file();
        }
        if ctx.input(|i| i.modifiers.ctrl && i.key_pressed(egui::Key::S)) {
            if ctx.input(|i| i.modifiers.shift) {
                self.save_file_as();
            } else {
                self.save_file();
            }
        }
        if ctx.input(|i| i.modifiers.ctrl && i.key_pressed(egui::Key::Q)) {
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }

        // Main text editor area
        egui::CentralPanel::default().show(ctx, |ui| {
            egui::ScrollArea::both()
                .auto_shrink([false, false])
                .show(ui, |ui| {
                    let response = ui.add_sized(
                        ui.available_size(),
                        egui::TextEdit::multiline(&mut self.text)
                            .font(egui::TextStyle::Monospace)
                            .code_editor()
                            .desired_width(f32::INFINITY)
                            .lock_focus(true),
                    );

                    if response.changed() {
                        self.modified = true;
                        self.status_message.clear();
                    }
                });
        });
    }
}

impl EditApp {
    fn new_file(&mut self) {
        if self.modified {
            // TODO: Ask to save changes
        }

        self.text = String::new();
        self.current_file = None;
        self.modified = false;
        self.status_message = "New file created".to_string();
    }

    fn open_file(&mut self) {
        if let Some(path) = rfd::FileDialog::new().pick_file() {
            match std::fs::read_to_string(&path) {
                Ok(contents) => {
                    self.text = contents;
                    self.current_file = Some(path.clone());
                    self.modified = false;
                    self.status_message = format!("Opened: {}", path.display());
                }
                Err(e) => {
                    self.status_message = format!("Failed to open: {} ({})", path.display(), e);
                }
            }
        }
    }

    fn save_file(&mut self) {
        if let Some(path) = &self.current_file {
            self.save_to_path(path.clone());
        } else {
            self.save_file_as();
        }
    }

    fn save_file_as(&mut self) {
        if let Some(path) = rfd::FileDialog::new().save_file() {
            self.save_to_path(path);
        }
    }

    fn save_to_path(&mut self, path: PathBuf) {
        match std::fs::write(&path, &self.text) {
            Ok(_) => {
                self.current_file = Some(path.clone());
                self.modified = false;
                self.status_message = format!("Saved: {}", path.display());
            }
            Err(e) => {
                self.status_message = format!("Failed to save: {} ({})", path.display(), e);
            }
        }
    }
}

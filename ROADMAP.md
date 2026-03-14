# 🛣️ HDD Catalogue — Feature Roadmap

> A living document tracking planned features, improvements, and ideas for HDD Catalogue.
> Prioritized for **video editors** managing projects across multiple external drives.

---

## ✅ Completed

### Core Features
- [x] Background drive detection & scanning (`NSWorkspace` notifications)
- [x] AI-powered project categorization (Google Gemini)
- [x] AI-powered duplicate detection across drives
- [x] Custom thumbnails (image drop, emoji, SF Symbol)
- [x] Client assignment with color coding
- [x] Menu bar quick-access & main catalogue window
- [x] Secure API key storage (macOS Keychain)
- [x] Launch at Login via `SMAppService`
- [x] Auto-scan on mount toggle
- [x] Multi-level scan depth (recursive project discovery)
- [x] System notifications (scan complete, new drive, duplicates)
- [x] Delete projects, drives, and clients
- [x] Client management (rename, recolor, merge)
- [x] Export to CSV / JSON
- [x] Advanced filtering (type, date range, size)
- [x] Undo / Redo for project edits, client changes, thumbnail changes, deletions, and merges (⌘Z via `UndoManagerService`)

### Phase 1 — Video Editor Essentials ✅
- [x] **NLE Project Detection** — scans for `.prproj`, `.fcpbundle`/`.fcpxml`, `.drp`, `.aep`, `.sesx`, `.mogrt`; shows NLE icon badges on cards; NLE is a filterable property; uses NLE project file date as the project's last-modified date
- [x] **Auto Video Thumbnails** — extracts frames from `.mp4`/`.mov`/`.mxf` via `AVAssetImageGenerator`; falls back to emoji/icon; cached in SwiftData
- [x] **Media Summary per Project** — counts video, audio, graphics, fonts, and renders; stacked bar breakdown in detail view; dominant media type shown as badge on cards
- [x] **Render/Export Detection** — identifies `Renders/`, `Exports/`, `Deliverables/`, `Output/` folders; shows "Delivered ✓" badge on cards when exports contain files
- [x] **Camera Source Detection** — detects camera-named subfolders (Sony, Blackmagic, Canon, RED, Panasonic, etc.); shows camera badges; counts multi-cam sources; flags drone/aerial footage (DJI, Mavic, FPV)
- [x] **Shoot-Day Grouping** — detects numbered shoot folders (`proizvodnja`, `shoot day`, date-based); shows shoot-day count; lists shoot-day folders in detail view
- [x] **Project Structure View** — detail view with project checklist (sources, NLE, exports); subfolder categorization (NLE workspace, materials, audio, graphics, source footage); completeness indicator ring (0–100%)

---

## ⚡ Phase 2 — Search & Workflow

> Find anything instantly, track project status.

### 🔍 Global Quick Search (⌘K) ✅
- [x] Spotlight-style overlay search across all drives (including disconnected)
- [x] Search by project name, client, type, NLE, tags, notes, cameras, status
- [x] Keyboard-navigable results with instant preview (↑↓ navigate, ↩ open, ⌘↩ Finder)
- [x] Jump to project card or reveal in Finder

### 🧠 AI Visual Search *(inspired by Diem)* ✅
- [x] Search by visual content — objects, moods, scenes ("sunset", "interview", "underwater")
- [x] Use Gemini Vision or CLIP embeddings to index thumbnails and video frames
- [x] "Find similar" — select a clip/image and surface visually similar files across all drives
- [x] Natural language queries ("all Premiere projects from last month over 10GB")

### 🏷️ Tag System ✅
- [x] Custom user tags per project (e.g. `#urgent`, `#archived`, `#youtube`)
- [x] Autocomplete from existing tags
- [x] Filter sidebar by tags
- [x] Tags displayed on project cards and in detail/edit views

### 📂 Smart Bins (Saved Searches) ✅ *(inspired by Diem)*
- [x] Create dynamic smart bins that auto-populate based on filter criteria
- [x] Criteria: NLE type, status, size, camera source, tags, search text
- [x] New projects matching criteria appear automatically after scans
- [x] Smart bins section in sidebar with add/edit/delete

### 📝 Quick Notes per Project ✅
- [x] Inline text field on project edit/detail views for personal notes
- [x] Notes searchable via global search (⌘K)

### 🔄 Project Status Workflow ✅
- [x] Status pipeline: `New → In Progress → Review → Delivered → Archived`
- [x] Visual status indicator on project cards (color-coded icon badge)
- [x] Filter and sort by status (sidebar + filter bar)
- [x] Status editable via context menu and edit sheet

### 📅 Recently Modified Dashboard ✅
- [x] "Home" view showing recently changed projects across all drives
- [x] Timeline view grouped by Today / This Week / This Month / Earlier
- [x] Stats header with total projects, in-progress count, drive count, recent activity
- [x] Dashboard + grid integrated — stats pills and grouped sections above the project grid when no filters active

### 🎛️ Premium Filter Bar ✅
- [x] Redesigned filter bar with chip-based UI — each filter has its own icon and accent color
- [x] Active filter highlighting with tinted backgrounds and colored borders
- [x] Active filter count badge + animated "Clear All" button
- [x] Properly interactive date pickers (From/To) with clear buttons
- [x] Subtle gradient background tint when filters are active

---

## 💾 Phase 3 — Drive & Storage Intelligence

> Understand your storage situation at a glance.

### 📈 Storage Dashboard
- [ ] Total storage used across all catalogued drives
- [ ] Storage breakdown per client (pie/bar chart)
- [ ] Growth trends over time (track catalogue snapshots)
- [ ] "Which drive has the most free space?" quick answer
- [ ] Some drives are SSDs and some are HDDs. We always want to keep ssds free and offload as much as possible to HDDs. 

### 📦 Archive Suggestions
- [ ] AI-powered suggestions for projects that could be archived
- [ ] Criteria: last modified > 6 months, deliverables present, not tagged as active
- [ ] One-click "mark as archived" action
- [ ] Archive report showing potential space savings

### 🔄 Drive Comparison View
- [ ] Side-by-side view of two drives
- [ ] Highlight projects that exist on both (backups)
- [ ] Identify projects only on one drive (not backed up)
- [ ] Useful for manual backup verification

### 🔎 File Type Search
- [ ] "Where did I put that?" — search for specific file types across all projects
- [ ] Find all projects containing `.mogrt`, `.prproj`, `.r3d`, etc.
- [ ] Results grouped by drive with file counts

### 🔬 Deep File Metadata Inspector *(inspired by Diem)*
- [ ] Per-file metadata panel: codec, pixel format, bitrate, frame rate, resolution
- [ ] Camera info: model, lens, ISO, shutter speed, white balance
- [ ] Timecode display for video files
- [ ] GPS location extraction (from EXIF/XMP) with coordinates display
- [ ] Color space and gamma info for professional grading workflows

---

## 🔮 Phase 4 — Polish & Platform

> Refinements, integrations, and quality-of-life.

### 🎨 App Icon
- [ ] Design a proper app icon (external drive + catalogue concept)

### ♿ Accessibility
- [ ] VoiceOver labels for all interactive elements
- [ ] Keyboard navigation for grid and sidebar
- [ ] Reduced motion alternatives for animations

### 🔌 IOKit Drive Detection
- [ ] Read drive serial numbers and hardware type (HDD/SSD/NVMe) via IOKit
- [ ] Show drive type icon in sidebar
- [ ] Better drive identity tracking across mounts

### 🔗 Spotlight Integration
- [ ] Register catalogued projects with macOS Spotlight
- [ ] `⌘Space` finds your projects system-wide
- [ ] Deep link from Spotlight result → catalogue view

### ✋ Drag to Organize
- [ ] Drag projects between clients in grid view to reassign
- [ ] Drag to reorder within a client group

### 🧪 Testing
- [ ] Unit tests for `ScanEngine`, `GeminiService`, `ExportService`
- [ ] UI tests for key flows (scan, filter, delete, export)
- [ ] Mock `ModelContext` for isolated service testing

---

## 🎥 Phase 5 — Pro Media Intelligence *(inspired by Diem)*

> Advanced features for professional video workflows — close the gap with DAM tools.

### 🗂️ Deep Media Index — Full File-Level Catalogue ✅
- [x] **File-level scanning** — index every file inside every project folder (not just project root)
  - [x] Record filename, path, size, type, dates for each file
  - [x] Build searchable file tree per project (expandable in drawer)
  - [x] Show total file breakdown: video / audio / image / project files / other
- [x] **Video frame analysis** — extract keyframes at intervals (every 30s or per scene change)
  - [x] Run Apple Vision `VNClassifyImageRequest` on each keyframe
  - [x] Store per-clip visual tags: scenes, objects, moods, actions
  - [x] "Find the clip with the sunset" across ALL drives, even disconnected
- [x] **Image classification** — classify all image files (photos, renders, stills, textures)
  - [x] Apple Vision tags for every `.jpg`, `.png`, `.tiff`, `.exr`, `.psd`
  - [x] Search: "show me all photos with people" or "find exterior shots"
- [x] **Metadata extraction** — deep media metadata for every file
  - [x] Video: codec, resolution, frame rate, duration, color space, bitrate
  - [x] Photo: EXIF (camera model, ISO, shutter speed, GPS, lens)
  - [x] Audio: sample rate, channels, codec, duration
  - [x] Filter by specs: "all 4K 120fps clips" or "all ProRes 422 HQ files"
- [x] **Full-catalogue search** — unified search across ALL files on ALL drives
  - [x] Search by filename, visual tags, metadata, file type
  - [x] Results show file path, parent project, drive (connected/disconnected status)
  - [ ] Preview files inline (video scrubbing, image zoom, audio waveform)
- [x] **Re-index on demand** — toolbar button to re-scan visual tags for selected projects/drives
  - [x] Incremental: only index new or modified files since last scan
  - [x] Background indexing with progress panel (non-blocking)
- [x] **Offline catalogue** — all metadata and tags stored locally
  - [x] Browse and search your entire media library even with all drives disconnected
  - [ ] Low-res proxy thumbnails cached per file for offline preview

### 📂 Gather & Transfer
- [ ] Create "Albums" — collect files from multiple projects/drives into a working set
- [ ] Smart transfer: app tells you which drives to connect to complete a copy
- [ ] Copy gathered files to a destination drive or folder with progress tracking
- [ ] Useful for assembling media for a new edit from archived drives

### 👤 Face Recognition & Grouping
- [ ] Detect and group faces across all media using `Vision.framework`
- [ ] Name faces and search by person
- [ ] "Show me all projects featuring [person]" across all drives

### 🗺️ Map View (Places)
- [ ] Extract GPS coordinates from photo/video EXIF metadata
- [ ] Plot media locations on an interactive map
- [ ] Click a pin to see all files shot at that location
- [ ] Filter by region or draw a selection area

### 🎞️ RAW Video Playback
- [ ] Real-time playback of RAW formats: `.r3d` (RED), `.braw` (Blackmagic)
- [ ] Support for standard RAW photo formats (`.arw`, `.cr3`, `.dng`, `.nef`)
- [ ] Smooth scrubbing and frame-accurate preview

### 🎨 LUT Preview Overlay
- [ ] Apply viewing LUTs (`.cube`, `.3dl`) to LOG footage during preview
- [ ] Preset LUT library (S-Log3, V-Log, C-Log, etc.)
- [ ] Non-destructive — LUTs are for preview only, never baked in

### 🔧 In-App Stabilization
- [ ] Gyroscope-based stabilization for action/drone footage (Gyroflow-style)
- [ ] Preview stabilized result in-app without exporting
- [ ] Export stabilized clips directly

---

## 💡 Ideas (Unscheduled)

> Community suggestions and experimental ideas.

- [ ] Proxy media browser — view low-res proxies of video files offline
- [ ] Project templates — create new projects with standard folder structures
- [ ] Webhook / Zapier integration for project status changes
- [ ] iCloud sync for catalogue data across Macs
- [ ] Frame.io / Dropbox integration for delivery tracking
- [ ] Dark/light theme toggle (currently follows system)
- [ ] Menubar quick-search widget
- [ ] Cloud storage integration — Google Drive, Dropbox, S3 as virtual "drives" *(Diem parity)*
- [ ] Cloud streaming — preview cloud files without downloading full assets *(Diem parity)*
- [ ] 3D drive visualizations — show realistic renders of drive models (LaCie, Glyph, etc.)
- [ ] Multi-sync depth modes — metadata-only, light sync (previews), deep sync (full index)

---

*Last updated: 14 March 2026*

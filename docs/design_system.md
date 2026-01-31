# Wispr Clone Design System

## Core Aesthetics

- **Philosophy**: Modern, minimalistic, and "magical".
- **Color Palette**:
  - Primary: `Color.white` (Text/Icons)
  - Accents: Gradient overlays (Red/Blue/Green for waveform).
  - Backgrounds: **Fully Transparent**. We avoid opaque "glass" containers for the HUD to ensure it feels like it's floating directly on the screen.

## Components

### Floating HUD (Recording)

- **Shape**: Compact Capsule (~122x44pt).
- **Behavior**: Appears instantly on `Option+Space`, disappears instantly on release.
- **Visuals**:
  - No background fill (0% opacity).
  - No stroke/border.
  - Content: High-contrast, animated waveform bars.
  - Animation: "Breathing" sine wave + Audio Level reaction (Power curve 0.8).

### Floating HUD (Processing)

- **Behavior**: Persistent until text is pasted.
- **Visuals**:
  - Icon: `hourglass` (SF Symbol).
  - Animation: `.pulse.byLayer` (Repeating).
  - Overlay: Glass capsule with subtle rim light.

### Menu Bar

- **Icon**: `waveform.circle` / `recordingtape.circle.fill`.
- **States**: Lazy loaded on first use.

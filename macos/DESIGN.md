# Retto desktop overlay exploration

Purpose: show Claude Code state without belonging to any editor window. Context: Luxia moves between macOS Spaces and full-screen apps. Constraints: transparent native window, low CPU use, readable against arbitrary wallpapers, draggable without a title bar, and no network dependency.

| # | Concept | Aesthetic | Probability | Creativity | Rationale |
|---|---|---:|---:|---:|---|
| 1 | Desktop Card | soft utility card | 33% | 3 | Obvious widget treatment; too much chrome. |
| 2 | Menu Bar Only | brutally minimal | 28% | 4 | Practical, but loses the emotional pet presence. |
| 3 | Traveling Plush | playful/toy-like | 7% | 9 | A transparent plush Retto carries one embroidered status ribbon across Spaces. |
| 4 | Cat-shaped Notch | geometric | 9% | 8 | Memorable, but depends too much on screen geometry. |
| 5 | Tiny Stage Light | cinematic | 11% | 7 | Strong state lighting but adds visual clutter over work. |
| 6 | Desk-edge Perch | spatial illusion | 6% | 9 | Retto appears to sit on the screen edge; awkward on multi-monitor layouts. |
| 7 | Polaroid Companion | editorial | 8% | 7 | Warm and tactile, but behaves like a floating card. |
| 8 | Status Collar | organic minimal | 5% | 9 | State appears as a small collar tag; may be too subtle. |
| 9 | Cloud Basket | dreamy soft | 8% | 8 | Cute but visually separates Retto from the desktop. |
| 10 | Cursor Familiar | game-like | 6% | 8 | Follows the cursor; potentially distracting during focused work. |

Selected: **Traveling Plush**. The sprite itself stays dominant and transparent. A compact oatmeal ribbon anchors the status value without turning the pet into a dashboard. It is memorable, readable on any desktop, and scales to future AI sources.

## Multi-session interaction exploration

| # | Pattern | Core behavior | Probability | Creativity | Decision |
|---|---|---|---:|---:|---|
| 1 | Auto Focus Familiar | Follow the highest-priority session; allow a manual pin | 24% | 8 | Selected: calm by default and useful when attention is needed |
| 2 | One Pet Per Session | Spawn one floating pet for every Claude session | 18% | 7 | Too much desktop clutter |
| 3 | Session Carousel | Click arrows to rotate through sessions | 13% | 5 | Important waits can remain hidden |
| 4 | Stacked Name Tags | Show every active session under the pet | 11% | 6 | Becomes a dashboard at small sizes |
| 5 | Menu-only Switcher | Keep the pet simple; choose sessions only in the menu | 14% | 3 | Weak ambient awareness |
| 6 | Orbiting Badges | Each session becomes a dot orbiting Retto | 4% | 9 | Cute but hard to label accessibly |
| 7 | Pet + Timeline | Show recent hook events next to the sprite | 5% | 6 | Visually heavy for an always-on overlay |
| 8 | Bell Collar | A collar badge counts sessions needing attention | 3% | 9 | Selected as a supporting signal |
| 9 | Project Aura | Tint the pet shadow by project | 4% | 8 | Project colors would need configuration |
| 10 | Session Dock | Snap a row of session icons to a screen edge | 4% | 7 | Conflicts with multi-monitor and Stage Manager layouts |

Selected interaction: **Auto Focus Familiar + Bell Collar**. Waiting, failure, active work, completion, and idle are ranked in that order. The user can pin any live session from the paw menu, return to automatic focus, and click Retto to open the exact Claude Code session in VS Code.

# NeOS Development Roadmap

## Scope and Philosophy
NeOS is a curated rolling-release, Arch-based desktop OS targeting stability through predictable behavior and staged updates. The roadmap focuses on build reliability, user experience parity with Windows, and maintainable long-term operations.

## Phase 0: Foundation and Planning
**Goals**
- Establish project standards, repository structure, and contributor documentation.
- Define build pipeline requirements and QA expectations.

**Key Deliverables**
- Project conventions (coding style, packaging policy, release cadence).
- CI/CD plan for repo builds and ISO generation.
- Baseline KDE Plasma configuration and UX principles.

## Phase 1: Build System and ISO Creation
**Goals**
- Build reproducible NeOS installation media.
- Automate ISO generation with staged repos and curated defaults.

**Workstreams**
1. **Build system**
   - Use Arch ISO build tooling (e.g., `archiso`) as a base.
   - Create a dedicated NeOS profile with custom packages and configs.
   - Automate ISO builds via CI for nightly and release candidates.
2. **Base image defaults**
   - Preconfigure KDE Plasma defaults.
   - Integrate Calamares with NeOS branding and default options.
   - Add default apps (Brave, VLC, nomacs, Thunderbird, LibreOffice).

**Acceptance Criteria**
- ISO reproducibility across CI environments.
- Successful clean install in VM with minimal manual setup.

## Phase 2: Repository and Update Strategy
**Goals**
- Define a reliable staging pipeline and update channel strategy.

**Workstreams**
1. **Repository topology**
   - Mirror Arch repos.
   - Create NeOS-curated repos for KDE, Qt, drivers, and firmware.
2. **Update gates**
   - Automated smoke testing for KDE/Qt updates.
   - Manual QA for desktop-critical changes.
3. **Release process**
   - Staged rollout: *staging → stable*.
   - Keep rollback packages for critical components.

**Acceptance Criteria**
- Staging repo receives new KDE/Qt versions before stable.
- Regression detection workflow documented and proven.

## Phase 3: Installer and First-Boot Experience
**Goals**
- Deliver a Windows-like, low-friction installer and a polished first-boot flow.

**Workstreams**
1. **Calamares customization**
   - Streamline the installer with sensible defaults.
   - Optional advanced mode for partitioning and custom packages.
2. **First-boot wizard**
   - Offer post-install updates.
   - Run driver detection and firmware installation.
   - Provide privacy and telemetry options.

**Acceptance Criteria**
- Installer feels consistent and branded.
- New user can reach a usable desktop with no terminal steps.

## Phase 4: Hardware and Driver Handling
**Goals**
- Ensure zero-friction hardware enablement for typical users.

**Workstreams**
1. **Driver automation**
   - Detect Nvidia GPUs and install proprietary drivers.
   - Integrate dkms module handling for kernel updates.
2. **Firmware coverage**
   - Curate Wi-Fi and laptop firmware packages in NeOS repos.
3. **Hardware quirks**
   - Default power profiles and known quirks presets.

**Acceptance Criteria**
- Nvidia users boot to working graphics by default.
- Common laptops function without manual driver installs.

## Phase 5: Security Defaults and Sandboxing
**Goals**
- Balance usability with sensible security defaults.

**Workstreams**
1. **System hardening**
   - Adopt secure kernel/sysctl defaults where practical.
2. **App sandboxing**
   - Prefer Flatpak for GUI apps when possible.
   - Ensure KDE portals are correctly configured.
3. **Policy documentation**
   - Clear guidelines for app confinement and exceptions.

**Acceptance Criteria**
- Flatpak-compatible apps integrate smoothly.
- Security policies are documented and enforceable.

## Phase 6: UX Familiarity and Polish
**Goals**
- Make NeOS familiar to Windows users while maintaining KDE quality.

**Workstreams**
1. **UI layout**
   - Ship a taskbar and launcher layout similar to Windows expectations.
   - Adjust default shortcuts to avoid surprises.
2. **Theme and branding**
   - Consistent default theme, iconography, and boot visuals.
3. **App defaults**
   - Set sensible default applications and file associations.

**Acceptance Criteria**
- Users can navigate without learning KDE conventions from scratch.
- Visual consistency across desktop and bundled apps.

## Phase 7: Long-Term Maintenance and Distribution
**Goals**
- Sustain NeOS as a publicly distributed OS.

**Workstreams**
1. **Release operations**
   - Define stable and testing channels.
   - Document how updates are promoted.
2. **Support and feedback**
   - Issue tracking and community support channels.
3. **Legal and licensing**
   - Compliance with upstream licenses and redistribution rules.

**Acceptance Criteria**
- Consistent update cadence and rollback plan.
- Clear governance and contributor workflows.

## Best-Practice Recommendations (Windows Familiarity + KDE Idioms)
- **Discover as the app store:** Keep Discover as the primary software hub to avoid fragmenting the user experience.
- **Minimal tray noise:** Curate background services and notifications by default.
- **Familiar shortcuts:** Provide Windows-like keybindings while documenting KDE equivalents.
- **File manager defaults:** Configure Dolphin for a clean, no-surprise layout.
- **Settings clarity:** Group system settings to avoid decision fatigue.

## Risks and Pitfalls (Arch-Based Distribution)
- **Upstream breakage:** Arch updates can break KDE or drivers unexpectedly.
- **Resource overhead:** Staging updates requires QA capacity and infrastructure.
- **Driver regressions:** Nvidia and Wi-Fi components are frequent sources of instability.
- **User expectations:** Rolling release may conflict with “set-and-forget” expectations.
- **Fork fatigue:** Excessive divergence from Arch increases maintenance costs.

## Success Metrics
- **Install success rate:** High completion rate in telemetry-free test cohorts.
- **Update reliability:** Minimal rollback usage after updates.
- **Support volume:** Low volume of driver and installation issues.
- **User satisfaction:** Positive feedback on usability and polish.

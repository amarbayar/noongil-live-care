# Noongil Accessibility Statement

**Last Updated:** March 10, 2026

---

## Our Commitment

Noongil is designed for people with motor dysfunction, including Parkinson's disease, ALS, multiple sclerosis, and arthritis. Accessibility is central to our product — not an afterthought.

We are committed to ensuring that the Noongil app is usable by as many people as possible, including those who rely on assistive technologies.

---

## Current Accessibility Features

### Voice-First Design
- The app is designed around voice interaction. All core features — daily check-ins, medication reminders, and wellness tracking — can be completed entirely through conversation without touching the screen.
- Three conversation modes accommodate varying connectivity and preference needs.

### VoiceOver Support
- Over 50 accessibility labels throughout the app provide meaningful descriptions for screen reader users.
- All interactive elements, buttons, and navigation controls are labeled for VoiceOver.
- Visual state indicators (connection status, model readiness) have corresponding text descriptions.

### Motor Accessibility
- Minimum touch target size of 60 points across all interactive elements, exceeding Apple's recommended 44-point minimum.
- No gestures requiring pinch, long-press, or multi-finger interaction.
- Simple, single-tap interactions for all controls.

### Reduce Motion
- Respects the system "Reduce Motion" accessibility setting across more than 10 animation sites.
- When Reduce Motion is enabled, animations are replaced with simple opacity transitions.

### Visual Design
- High contrast text and UI elements on dark backgrounds.
- The companion orb provides visual feedback through color and glow changes, not motion alone.
- Glass card UI provides clear visual hierarchy and separation.

---

## Known Gaps and Roadmap

We are transparent about areas where we are continuing to improve:

### Dynamic Type (In Progress)
- The app does not yet fully support Dynamic Type for text scaling. Users who rely on large text sizes may encounter truncated or overlapping text in some views.
- **Target:** Full Dynamic Type support across all views.

### Switch Control (Planned)
- Custom actions for Switch Control users have not yet been implemented. Basic navigation works, but custom flows (like the conversation interface) may require additional Switch Control accommodations.
- **Target:** Switch Control custom actions for all primary workflows.

### Color Contrast Ratio
- While the app generally provides high contrast, some secondary text elements may not meet WCAG 2.1 AA contrast ratio requirements (4.5:1 for normal text, 3:1 for large text) in all theme configurations.
- **Target:** WCAG 2.1 AA compliance for all text elements.

---

## Standards

We are working toward compliance with:
- **WCAG 2.1** (Web Content Accessibility Guidelines) at Level AA
- **Apple Accessibility Programming Guide** for iOS
- **Section 508** of the Rehabilitation Act (for potential future government use)

---

## Feedback

We welcome feedback about the accessibility of Noongil. If you encounter accessibility barriers or have suggestions, please contact us:

**Email:** accessibility@noongil.ai

We aim to respond to accessibility-related feedback within 5 business days.

---

## Testing

We test accessibility through:
- VoiceOver manual testing on physical iOS devices
- Accessibility Inspector (Xcode) for label and trait verification
- User testing with members who have motor impairments
- Automated unit tests for accessibility label coverage

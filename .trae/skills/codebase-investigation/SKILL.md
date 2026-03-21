---
name: "codebase-investigation"
description: "Codebase investigation and analysis methodology. Invoke when needing to understand existing implementations, debug issues across multiple components, or standardize patterns across the codebase."
---

# Codebase Investigation Methodology

## Overview

This skill provides a systematic approach to investigating and analyzing existing code implementations in a codebase. It helps prevent partial fixes and ensures comprehensive understanding before making changes.

## When to Invoke

- Before fixing bugs that may affect multiple components
- When standardizing patterns across the codebase
- When inheriting or refactoring legacy code
- When debugging issues that don't have clear root causes
- Before introducing new patterns that may conflict with existing ones

## The Investigation Process

### Phase 1: Discovery (Find All Related Code)

**Goal**: Locate ALL implementations related to the feature/pattern

**Actions**:
1. **Keyword Search**: Use grep to find all occurrences
   ```bash
   # Search for related terms
   grep -r "patternName" --include="*.swift" .
   grep -r "relatedTerm" --include="*.swift" .
   ```

2. **Identify Implementation Variants**: Look for:
   - Different files implementing the same pattern
   - Similar but slightly different implementations
   - Old vs new implementations
   - Core components vs custom implementations

3. **Map Dependencies**: Find:
   - Which components use the core implementation
   - Which components have custom implementations
   - Shared utilities and helpers

**Output**: A complete list of all files and their implementation approaches

### Phase 2: Analysis (Understand the Differences)

**Goal**: Understand WHY there are multiple implementations

**Actions**:
1. **Compare Implementations**: Create a comparison table
   | File | Approach | Key Differences | Pros/Cons |
   |------|----------|-----------------|-----------|
   | FileA.swift | Approach 1 | Uses X | Simple but limited |
   | FileB.swift | Approach 2 | Uses Y | Flexible but complex |

2. **Identify the "Source of Truth"**:
   - Which implementation is most complete?
   - Which is used by core components?
   - Which follows best practices?
   - Is there a designated "standard" implementation?

3. **Understand Context**:
   - Why were different approaches chosen?
   - Are there legitimate reasons for variations?
   - Are some implementations outdated?

**Output**: Understanding of which implementation should be the standard

### Phase 3: Standardization Decision

**Goal**: Decide on the unified approach

**Decision Matrix**:
```
Criteria:
- Simplicity: Which is easier to understand and maintain?
- Completeness: Which handles all use cases?
- Performance: Which has better performance?
- Consistency: Which matches existing patterns?
- Adoption: Which is already most widely used?

Weight each criterion based on project needs, then score each approach.
```

**Output**: Clear decision on which approach to standardize

### Phase 4: Implementation Planning

**Goal**: Plan the changes needed to standardize

**Actions**:
1. **List All Changes**: For each file that needs updating
   - Current implementation
   - Required changes
   - Potential risks

2. **Determine Order**:
   - Start with core components
   - Then update dependent components
   - Test after each major change

3. **Identify Edge Cases**:
   - Special use cases that might need different handling
   - Backward compatibility concerns
   - Breaking changes

**Output**: Detailed implementation plan

### Phase 5: Execution and Verification

**Goal**: Implement changes and verify consistency

**Actions**:
1. **Make Changes**: Following the plan
2. **Test Thoroughly**:
   - Test all affected components
   - Verify the fix works in all scenarios
   - Check for regressions

3. **Document**:
   - Update code comments
   - Update skills/documentation
   - Add examples for future reference

## Common Investigation Patterns

### Pattern 1: The "Multiple Implementations" Problem

**Symptom**: Same feature works differently in different places

**Example**: Card background with tint opacity
- CardBackgroundView.swift: Uses approach A
- ThemePreviewSection.swift: Uses approach A
- MeView.swift: Uses approach B
- SettingsGridItem.swift: Uses approach B

**Solution**:
1. Identify both approaches
2. Decide which to standardize
3. Update all files to use the same approach
4. Document the standard

### Pattern 2: The "Partial Fix" Problem

**Symptom**: Fix works in some places but not others

**Root Cause**: Only fixed one implementation, missed others

**Prevention**: Always do Phase 1 (Discovery) before making changes

### Pattern 3: The "Wrong Abstraction" Problem

**Symptom**: Using a component, but it doesn't behave as expected

**Example**: Using CardBackgroundView but tint doesn't work

**Investigation**:
1. Check CardBackgroundView's implementation
2. Compare with working implementations
3. Identify the difference
4. Fix the core component, not just the usage

## Tools and Techniques

### 1. Grep Search Patterns

```bash
# Find all implementations of a pattern
grep -r "patternName" --include="*.swift" . | grep -v ".build"

# Find related terms
grep -r "termA\|termB\|termC" --include="*.swift" .

# Find in specific directories
grep -r "patternName" --include="*.swift" ./ItemManager/Views
```

### 2. IDE Features

- **Find Usages**: Find all places a component is used
- **Go to Definition**: Understand the implementation
- **Compare Files**: Side-by-side comparison of implementations

### 3. Documentation

- Create a comparison table
- Document the "why" behind each implementation
- Update skills with findings

## Red Flags (When to Investigate)

1. **"It works here but not there"**: Likely multiple implementations
2. **"I fixed it but it's still broken"**: Missed some implementations
3. **"This component should work but doesn't"**: Wrong abstraction or usage
4. **"The code looks right but behaves wrong"**: Hidden implementation details
5. **"The color shows as black/dark"**: Check default configuration and color source

## Systematic Investigation Process (Updated)

### Critical First Steps

**BEFORE any deep investigation, ALWAYS**:

1. **Check Default Configuration Values**
   ```bash
   # Find default values
   grep -r "var.*= .*\.classic\|var.*= .*\.default" --include="*.swift" .
   ```
   
   **Why**: Many issues stem from assuming users will change defaults. They won't.

2. **Find the Working Counterpart**
   - Where does this feature work correctly?
   - Use that as your reference implementation
   
   **Example**: 
   - Theme preview shows correct colors → Reference
   - PetChatView shows black background → Problem

3. **Compare Line by Line**
   - Open both implementations side by side
   - Look for differences in color sources
   - Identify the exact line causing the issue

### Root Cause Analysis Framework

When investigating color/theme issues:

```
Surface Symptom: Black background
  ↓
Check 1: Is there an overlay covering it?
  → No: Continue
  ↓
Check 2: Is ScrollView background causing it?
  → No: Continue
  ↓
Check 3: What is the actual background color value?
  → Color(.systemBackground) - This is it!
  ↓
Check 4: Where does this color come from?
  → Hard-coded in classic skin branch
  ↓
Check 5: What should it be?
  → themeManager.cardBackgroundColor (like the working version)
  ↓
Root Cause: Classic skin uses system color instead of theme color
```

### Common Investigation Pitfalls (Learned from Experience)

**Pitfall 1: Assuming the Problem Location**
- **Symptom**: Black background
- **Wrong assumption**: Something is covering it
- **Reality**: The background color itself is wrong
- **Lesson**: Check the actual value first

**Pitfall 2: Not Checking Defaults**
- **Assumption**: User will select magic skin
- **Reality**: Default is classic skin
- **Lesson**: Always handle default configuration

**Pitfall 3: Over-engineering the Solution**
- **Wrong approach**: Create complex color calculation methods
- **Right approach**: Use the same simple approach as the working version
- **Lesson**: Simplicity wins

**Pitfall 4: Not Tracing the Full Chain**
- **Wrong**: Just check the immediate usage
- **Right**: Trace from usage to source
- **Lesson**: Follow the complete data/color flow

### Investigation Checklist (Updated)

Before making any changes:

- [ ] Checked default configuration values
- [ ] Found the working counterpart/counterexample
- [ ] Compared implementations line by line
- [ ] Identified the exact difference
- [ ] Traced the color/data source completely
- [ ] Verified the root cause (not just symptoms)
- [ ] Proposed solution matches the working pattern
- [ ] Documented findings for future reference

## Updated Example: PetChat Bubble Color Investigation

### Problem
PetChat bubbles show black background in dark mode, but theme preview shows correct colors.

### Investigation Steps

1. **Check Defaults**
   ```swift
   var petChatSkinTheme: PetChatSkinTheme = .classic  // ← Default is classic!
   ```

2. **Find Working Version**
   - ThemePreviewSection.swift: Works correctly
   - Uses: `themeManager.cardBackgroundColor`

3. **Compare with Problem Version**
   ```swift
   // PetChatView.swift - Classic skin branch
   .fill(Color(.systemBackground))  // ← Problem!
   
   // ThemePreviewSection.swift
   .fill(themeManager.cardBackgroundColor)  // ← Correct
   ```

4. **Root Cause**
   - Classic skin used system color instead of theme color
   - `Color(.systemBackground)` is black in dark mode

5. **Solution**
   ```swift
   // Change to match working version
   .fill(themeManager.cardBackgroundColor)
   ```

### Lessons Learned

1. **Always check defaults** - Don't assume user configuration
2. **Find the working counterpart** - It's your best reference
3. **Compare line by line** - Differences are often obvious once seen
4. **Trace the source** - Follow the complete chain
5. **Keep it simple** - Don't over-engineer

## Integration with Other Skills

This investigation skill should be used BEFORE:
- `swiftui-theme-adaptation`: To understand existing theme patterns
- `swiftui-theme-color-adaptation`: To identify color adaptation issues
- `swiftui-card-background-tint`: To understand tint implementations
- Any refactoring or standardization task

The output of this skill (investigation report) becomes input for implementation skills.

**Important**: Use the systematic investigation process above, especially the "Critical First Steps" section, to avoid common pitfalls.

## Example Investigation Report

```markdown
## Investigation: Card Background Tint Implementation

### Discovery
Found 7 files with tint-related implementations:
- CardBackgroundView.swift (core component)
- ThemePreviewSection.swift (preview)
- MeView.swift (custom implementation)
- SettingsGridItem.swift (custom implementation)
- AccountCard.swift (custom implementation)
- iCloudStatusCard.swift (custom implementation)
- MagicThemeDesignSystem.swift (segmented background)

### Analysis
Two distinct approaches identified:

**Approach A: Pure Tint**
- Used by: CardBackgroundView, ThemePreviewSection
- Implementation: `color.opacity(tintOpacity)`
- Pros: Simple, performant
- Cons: No glass effect

**Approach B: Glass + Tint Overlay**
- Used by: MeView, SettingsGridItem, AccountCard, iCloudStatusCard
- Implementation: `.ultraThinMaterial` + overlay
- Pros: Glass effect, visual depth
- Cons: More complex, potential performance impact

### Decision
Standardize on Approach A for most components.
Approach B reserved for special cards needing glass effect.

### Changes Required
1. Update CardBackgroundView (already correct)
2. Update MagicThemeDesignSystem segmented background
3. Document both approaches for future use

### Verification
- Test all card backgrounds
- Test segmented controls
- Test in both light and dark mode
```

## Integration with Other Skills

This investigation skill should be used BEFORE:
- `swiftui-theme-adaptation`: To understand existing theme patterns
- `swiftui-card-background-tint`: To understand tint implementations
- Any refactoring or standardization task

The output of this skill (investigation report) becomes input for implementation skills.

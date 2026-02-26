---
name: "backup-compatibility"
description: "Ensures backward compatibility for data backup and restore functionality in iOS apps. Invoke when adding new fields to backup DTOs, implementing backup/restore features, or fixing compatibility issues with old backup files."
---

# Backup Compatibility Best Practices

## When to Use This Skill

- Adding new fields to backup DTOs (Data Transfer Objects)
- Implementing backup/restore functionality
- Fixing "Missing key" or decoding errors with old backup files
- Refactoring backup service code
- Adding soft delete or sync features to data models

## Core Principles

### 1. All New Fields Must Be Optional

When adding any new field to a DTO, always make it optional:

```swift
// ❌ Wrong - will break old backups
let isDeleted: Bool

// ✅ Correct - backward compatible
let isDeleted: Bool?  // v1.4+ soft delete flag
```

### 2. Add Version Comments

Always document when the field was introduced:

```swift
struct ClothingDTO: Codable {
    // Basic fields (required)
    let id: UUID
    let name: String
    
    // v1.2+ new fields
    let isShared: Bool?
    let sortIndex: Int?
    
    // v1.3+ custom accessories
    let accessoryItems: [AccessoryItemDTO]?
    
    // v1.4+ soft delete support
    let isDeleted: Bool?
    let deletedAt: Date?
    let lastModified: Date?
}
```

### 3. Provide Default Values in Restore Logic

Always handle optional values with defaults:

```swift
// Boolean - default false
clothing.isDeleted = dto.isDeleted ?? false
model3D.isDeleted = dto.isDeleted ?? false

// Numeric - default 0
clothing.accessoriesPrice = dto.accessoriesPrice ?? 0
clothing.sortIndex = dto.sortIndex ?? 0
model3D.cameraPositionX = dto.cameraPositionX ?? 0

// Enum - provide default case
clothing.status = ClothingStatus(rawValue: dto.status ?? "") ?? .onShelf

// String - default empty or reasonable value
clothing.nickname = dto.nickname ?? ""
```

### 4. Handle Optional in Conditionals

When checking optional booleans in conditions:

```swift
// ❌ Wrong - Bool? cannot be used directly
if dto.isDeleted { continue }

// ✅ Correct - provide default
if dto.isDeleted ?? false { continue }
```

## Field Type Guidelines

| Field Type | Should Be Optional | Default Value | Example |
|------------|-------------------|---------------|---------|
| New feature fields | ✅ Yes | Context-dependent | `isShared: Bool?` |
| Soft delete flags | ✅ Yes | `false` | `isDeleted: Bool?` |
| Sync timestamps | ✅ Yes | `nil` or `Date()` | `lastModified: Date?` |
| Sort indexes | ✅ Yes | `0` | `sortIndex: Int?` |
| Status enums | ✅ Yes | Default case | `status: String?` |
| Related IDs | ✅ Yes | `nil` | `bookID: UUID?` |
| Basic info (id, name) | ❌ No | N/A | `id: UUID`, `name: String` |
| Creation date | ❌ No | N/A | `createdAt: Date` |

## Common Patterns

### Pattern 1: Soft Delete Fields

```swift
// DTO definition
struct ItemDTO: Codable {
    let id: UUID
    let name: String
    // ... other basic fields
    
    // v1.4+ soft delete support
    let isDeleted: Bool?
    let deletedAt: Date?
}

// Restore logic
item.isDeleted = dto.isDeleted ?? false
item.deletedAt = dto.deletedAt

// Skip deleted items
if dto.isDeleted ?? false { continue }
```

### Pattern 2: Sync Timestamps

```swift
// DTO definition
struct ItemDTO: Codable {
    // ... basic fields
    
    // v1.4+ sync support
    let lastModified: Date?
}

// Restore logic
if let lastModified = dto.lastModified {
    item.lastModified = lastModified
}
```

### Pattern 3: Enum Status

```swift
// DTO definition
struct ItemDTO: Codable {
    // ... basic fields
    
    // v1.2+ status support
    let status: String?
}

// Restore logic
item.status = ItemStatus(rawValue: dto.status ?? "") ?? .default
```

### Pattern 4: Nested Arrays

```swift
// DTO definition
struct ItemDTO: Codable {
    // ... basic fields
    
    // v1.3+ nested items
    let subItems: [SubItemDTO]?
}

// Restore logic
if let subDTOs = dto.subItems {
    // Process sub-items
}
```

## Error Handling

Always implement detailed decoding error handling:

```swift
do {
    manifest = try jsonDecoder.decode(BackupManifest.self, from: manifestData)
} catch let decodingError as DecodingError {
    switch decodingError {
    case .keyNotFound(let key, let context):
        print("Missing key '\(key.stringValue)' in \(context.codingPath)")
        // Log: Missing key 'isDeleted' in [CodingKeys(stringValue: "snapshots", intValue: nil), _CodingKey(stringValue: "Index 0", intValue: 0)]
    case .typeMismatch(let type, let context):
        print("Type mismatch for \(type) in \(context.codingPath)")
    case .valueNotFound(let type, let context):
        print("Value not found for \(type) in \(context.codingPath)")
    case .dataCorrupted(let context):
        print("Data corrupted: \(context.debugDescription)")
    @unknown default:
        print("Unknown decoding error: \(decodingError)")
    }
    throw BackupError.invalidArchive
}
```

## Checklist for Adding New Fields

When adding a new feature that requires backup support:

1. **DTO Design**
   - [ ] Make new fields optional (`Type?`)
   - [ ] Add version comment (e.g., `// v1.5+`)
   - [ ] Group related fields together

2. **Backup Logic**
   - [ ] Directly read from model (no changes needed for optional fields)

3. **Restore Logic**
   - [ ] Provide default value using `??`
   - [ ] Handle in conditionals with `?? false`
   - [ ] Use `if let` for optional complex types

4. **Testing**
   - [ ] Test with old backup file (should succeed)
   - [ ] Test with new backup file (should succeed)
   - [ ] Verify default values are applied correctly

## Anti-Patterns to Avoid

### ❌ Force Unwrapping

```swift
// Dangerous - will crash if nil
clothing.status = ClothingStatus(rawValue: dto.status!)!
```

### ❌ Implicit Unwrapping in Conditions

```swift
// Won't compile or behave unexpectedly
if dto.isDeleted { ... }  // Bool? in condition
```

### ❌ Ignoring Optional

```swift
// Type mismatch error
clothing.isDeleted = dto.isDeleted  // Bool = Bool?
```

### ❌ Non-Optional New Fields

```swift
// Breaks backward compatibility
struct ItemDTO: Codable {
    let id: UUID
    let name: String
    let newField: String  // ❌ Old backups will fail
}
```

## Summary

Remember the golden rule: **When in doubt, make it optional (`?`) and provide a sensible default.**

This ensures:
- ✅ Old backup files always restore successfully
- ✅ New features work with new backups
- ✅ Graceful degradation for missing fields
- ✅ No crashes or data loss

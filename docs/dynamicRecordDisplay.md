# Dynamic Record Display (`dynamicRecordDisplay`)

> **Version:** 1.0.0 · **API Version:** 66.0 · **Platform:** Salesforce LWC (Aura-compatible)

A fully configurable Lightning Web Component that renders records from **any Salesforce object** in four distinct display modes. Designed for Aura-based Experience Cloud communities, it supports system-level queries, rich theming, badge/pill overlays, and admin-driven configuration via Experience Builder — with no code changes required after deployment.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [File Structure](#2-file-structure)
3. [Apex Controller](#3-apex-controller)
   - [Method Signature](#method-signature)
   - [Parameters](#parameters)
   - [Return Type — `RecordQueryResult`](#return-type--recordqueryresult)
   - [Security Model](#security-model)
   - [WHERE Clause Sanitisation](#where-clause-sanitisation)
4. [LWC Component](#4-lwc-component)
   - [Display Modes](#display-modes)
   - [Theming System](#theming-system)
   - [Badge / Pill System](#badge--pill-system)
   - [Grid Overlay](#grid-overlay)
   - [Pagination — Load More](#pagination--load-more)
   - [Record Navigation](#record-navigation)
   - [Carousel Controls](#carousel-controls)
5. [Admin Properties Reference](#5-admin-properties-reference)
6. [Experience Builder Setup](#6-experience-builder-setup)
7. [Deployment](#7-deployment)
8. [Test Coverage](#8-test-coverage)
9. [Responsive Behaviour](#9-responsive-behaviour)
10. [Accessibility](#10-accessibility)
11. [Known Constraints](#11-known-constraints)

---

## 1. Architecture Overview

```
Experience Builder Page
        │
        ▼
dynamicRecordDisplay (LWC)
  ├── connectedCallback → _loadRecords(false)
  ├── getRecords() [imperative Apex call]
  │         │
  │         ▼
  │   DRD_RecordDisplayController (without sharing)
  │     ├── validateRequiredInputs
  │     ├── describeObject        ← Schema.getGlobalDescribe()
  │     ├── buildFieldMetadata    ← Schema.SObjectField.getDescribe()
  │     ├── buildOrderByClause
  │     ├── sanitiseWhereClause   ← keyword blocklist
  │     └── Database.query(soql)
  │
  ├── processedRecords getter → UI-ready record objects
  │     ├── badge styling (_buildBadgeStyle)
  │     ├── grid overlay style (_buildOverlayStyle)
  │     └── primary / secondary field separation
  │
  └── Template renders one of:
        ├── drd-list-view      (stacked rows)
        ├── drd-card-grid      (3-col cards)
        ├── drd-carousel       (sliding 3-visible)
        └── drd-grid-view      (image + overlay)
```

---

## 2. File Structure

```
force-app/main/default/
├── classes/
│   ├── DRD_RecordDisplayController.cls          ← Apex controller
│   ├── DRD_RecordDisplayController.cls-meta.xml
│   ├── DRD_RecordDisplayControllerTest.cls      ← Test class (21 methods)
│   └── DRD_RecordDisplayControllerTest.cls-meta.xml
└── lwc/
    └── dynamicRecordDisplay/
        ├── dynamicRecordDisplay.html            ← Template (4 view modes)
        ├── dynamicRecordDisplay.js              ← Controller
        ├── dynamicRecordDisplay.css             ← 10 themes + all view styles
        └── dynamicRecordDisplay.js-meta.xml     ← Experience Builder properties
```

---

## 3. Apex Controller

**Class:** `DRD_RecordDisplayController`  
**Sharing model:** `without sharing`

### Method Signature

```apex
@AuraEnabled(cacheable=true)
public static RecordQueryResult getRecords(
    String  objectApiName,
    String  fieldListCsv,
    String  whereClause,
    String  orderByField,
    String  orderByDir,
    Integer queryLimit,
    Integer queryOffset
)
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `objectApiName` | `String` | ✅ | API name of the SObject to query (e.g. `Account`, `Grant__c`) |
| `fieldListCsv` | `String` | ✅ | Comma-separated field API names (e.g. `Name,Status__c,Amount__c`) |
| `whereClause` | `String` | ❌ | SOQL WHERE body without the `WHERE` keyword. Admin-configured only |
| `orderByField` | `String` | ❌ | Field API name to sort by (validated via Schema.describe) |
| `orderByDir` | `String` | ❌ | `ASC` (default) or `DESC` |
| `queryLimit` | `Integer` | ❌ | Records per page. Defaults to `10`; capped at `200` |
| `queryOffset` | `Integer` | ❌ | Records to skip for Load More pagination |

### Return Type — `RecordQueryResult`

```apex
public class RecordQueryResult {
    @AuraEnabled public List<Map<String, Object>> records;
    @AuraEnabled public Map<String, String> fieldLabels;   // fieldApiName → label
    @AuraEnabled public Map<String, String> fieldTypes;    // fieldApiName → type string
    @AuraEnabled public Boolean hasMore;                   // true if more pages exist
}
```

**Pagination detection:** the controller queries `limit + 1` records. If the result set contains `limit + 1` rows, `hasMore = true` and the extra row is discarded before returning. No separate COUNT query is needed.

**`Id` auto-inclusion:** `Id` is always prepended to the field list if absent, ensuring NavigationMixin can navigate to record detail pages.

### Security Model

| Concern | Approach |
|---------|----------|
| Object validation | `Schema.getGlobalDescribe().get(name)` — throws `AuraHandledException` if null |
| Field validation | `fieldMap.containsKey(trimmedName)` for every CSV entry — throws on first invalid field |
| ORDER BY validation | Same field map check before building the ORDER BY clause |
| WHERE clause | Admin-configured via Experience Builder, not end-user input; additionally sanitised against a keyword blocklist |
| Sharing | `without sharing` — intentional for community record visibility; site-level guest profile / permission sets control access |

### WHERE Clause Sanitisation

The following keywords are blocked (case-insensitive). Detection of any one raises an `AuraHandledException`:

```
DELETE  UPDATE  INSERT  UPSERT  UNDELETE  MERGE
DROP    CREATE  ALTER   TRUNCATE  EXECUTE  EXEC
UNION   INTERSECT  --  /*  */
```

---

## 4. LWC Component

### Display Modes

Set via the `displayMode` property (`list` | `card` | `carousel` | `grid`).

#### List Mode (`list`)

Records rendered as uniform grid-column rows inside a bordered container. Every row shares an
identical CSS column template, so values line up cleanly regardless of content length.

**Column layout**
- Each row uses a CSS Grid (`display: grid`) wrapper (`.drd-list-columns`) driven by the
  `--drd-list-col-template` CSS custom property injected by the `listViewStyle` JS getter.
- Template formula: the **first column gets `2fr`** (typically the Name / primary field),
  every subsequent inline column gets `1fr` — giving the name more breathing room while
  keeping other fields evenly spaced.
- The template is set once on the `.drd-list-view` container and inherited by every row,
  guaranteeing pixel-identical column widths across all records.

**Long-text / textarea fields**
- Fields whose Salesforce `Schema.DisplayType` resolves to `TEXTAREA`, `RICHTEXTAREA`, or
  `LONGTEXTAREA` are automatically classified as *long-text* fields.
- Long-text fields are **excluded from the inline column grid** and instead rendered as a
  full-width second row (`.drd-list-long-text`) below the column grid, separated by a
  subtle `border-top` rule.
- When a long-text field has no value, its row is hidden entirely — no empty "DESCRIPTION —"
  column appearing inline alongside the other fields.
- Place long-text fields **last in the `fieldList` CSV** to keep them visually grouped; the
  component processes fields in CSV order.

**Other behaviour**
- Alternating row background via CSS `color-mix()` against the theme accent
- Hover: indent `padding-left` to `28px` + `4px` left inset border in accent colour
- All non-long-text fields shown inline (label above value); badge fields render as pills
- On mobile (≤ 600 px) the column grid collapses to a single `1fr` column (fields stack)

#### Card Mode (`card`)

3-column CSS grid of cards with gradient headers.

- Card header: linear gradient from `--drd-header-bg` → blend with `--drd-accent`
- Primary field displayed as the card title in the header
- Secondary fields (all fields except primary) in the card body
- Hover: `translateY(-4px)` lift + elevated shadow + accent border
- "View Details ›" CTA in the card footer

#### Carousel Mode (`carousel`)

3 cards visible at once with CSS `translateX` sliding animation.

- Each card is `33.33%` wide within the track
- Navigation: circular prev/next buttons + dot indicators
- `isPrevDisabled` / `isNextDisabled` bound to button `disabled` attribute
- `carouselTrackStyle` computes `translateX(-N%)` where N = `carouselIndex × 33.33`
- `carouselDots` array drives ARIA tab-role dot buttons
- Load More appends new records to the track without resetting position

#### Grid Mode (`grid`)

3-column image grid with configurable overlay.

- Background: `background-image: url(imageUrl)` when `imageUrlField` resolves to a non-empty value; falls back to `var(--drd-accent)` solid colour
- Overlay (see [Grid Overlay](#grid-overlay)) is absolutely positioned over the image
- Hover: `scale(1.03)` with elevated shadow
- Primary value and badge fields shown inside the overlay

---

### Theming System

Themes are applied as CSS classes on the root `.drd-container` element: `drd-theme-{theme-name}`. Each theme defines 8 CSS custom properties.

#### Preset Themes

| Theme Name | `colorTheme` value | Accent | Header BG |
|------------|--------------------|--------|-----------|
| Ocean Blue | `ocean-blue` | `#0070D2` | `#032D60` |
| Forest Green | `forest-green` | `#2E7D32` | `#1B5E20` |
| Sunset Orange | `sunset-orange` | `#E65100` | `#BF360C` |
| Midnight Dark | `midnight-dark` | `#BB86FC` | `#121212` |
| Clean White | `clean-white` | `#0070D2` | `#FFFFFF` |
| Royal Purple | `royal-purple` | `#7B1FA2` | `#4A148C` |
| Rose Gold | `rose-gold` | `#C2185B` | `#880E4F` |
| Slate Gray | `slate-gray` | `#546E7A` | `#263238` |
| Teal Breeze | `teal-breeze` | `#00796B` | `#004D40` |
| Coral Reef | `coral-reef` | `#FF6F61` | `#C0392B` |

#### CSS Custom Properties

| Variable | Purpose |
|----------|---------|
| `--drd-accent` | Buttons, borders, highlights, left-border on hover |
| `--drd-header-bg` | Component header and card title bar background |
| `--drd-header-text` | Text colour on header/card title areas |
| `--drd-card-bg` | Card, list row, and grid item background |
| `--drd-card-border` | Border colour for cards and list rows |
| `--drd-text` | Body text colour |
| `--drd-text-muted` | Secondary text and empty state messages |
| `--drd-label-color` | Field label (uppercase micro-text) colour |

#### Custom Hex Overrides

Any of these `@api` properties set at the component level inject inline CSS variables that override the selected theme:

| Property | Overrides |
|----------|-----------|
| `accentColor` | `--drd-accent` |
| `headerBgColor` | `--drd-header-bg` |
| `cardBgColor` | `--drd-card-bg` |
| `textColor` | `--drd-text` |

---

### Badge / Pill System

Fields listed in `badgeFields` (CSV) are rendered as colored pill-shaped `<span>` elements instead of plain text.

#### Color Resolution Order

1. **Override map** (`badgeColorMap`): check if `displayValue.toLowerCase()` matches a key  
   - Format: `Active=#2E7D32,Closed=#C2185B,Pending=#E65100`  
   - Text contrast is auto-detected using relative luminance — dark bg → white text; light bg → `#1A1A1A` text
2. **Hash auto-color**: deterministic hash of `displayValue` modulo 12 color palette

#### 12-Color Auto-Palette

| # | Background | Text |
|---|-----------|------|
| 1 | `#0070D2` | `#FFFFFF` |
| 2 | `#2E7D32` | `#FFFFFF` |
| 3 | `#E65100` | `#FFFFFF` |
| 4 | `#7B1FA2` | `#FFFFFF` |
| 5 | `#C2185B` | `#FFFFFF` |
| 6 | `#00796B` | `#FFFFFF` |
| 7 | `#546E7A` | `#FFFFFF` |
| 8 | `#F57F17` | `#1A1A1A` |
| 9 | `#4527A0` | `#FFFFFF` |
| 10 | `#AD1457` | `#FFFFFF` |
| 11 | `#00838F` | `#FFFFFF` |
| 12 | `#558B2F` | `#FFFFFF` |

The same string value always maps to the same color (deterministic), so `Status = Active` will be the same shade everywhere the component is used.

#### Badge Styles

| `badgeStyle` | Appearance |
|--------------|-----------|
| `filled` (default) | Solid `bgColor` background, white or dark text |
| `outlined` | Transparent background, `bgColor` border and text |

Both styles: `border-radius: 12px`, `padding: 2px 10px`, `font-size: 0.75rem`, `font-weight: 600`.

#### Badge Display by Mode

| Mode | Badge location |
|------|---------------|
| `list` | Inline within each field row, replacing plain text |
| `card` | Inline within card body field rows |
| `carousel` | Inline within each carousel card's body |
| `grid` | Inside the image overlay (badge-only fields) |

---

### Grid Overlay

Applies only in `grid` mode. Computed by `_buildOverlayStyle()`.

| Property | `@api` name | Default |
|----------|-------------|---------|
| Background hex | `overlayBgColor` | `#000000` |
| Text hex | `overlayTextColor` | `#FFFFFF` |
| Opacity (0–100) | `overlayOpacity` | `60` |
| Direction | `overlayDirection` | `bottom-to-top` |

**Direction modes:**

| Value | CSS Output |
|-------|-----------|
| `bottom-to-top` | `linear-gradient(to top, rgba(r,g,b,opacity) 0%, rgba(r,g,b,0) 100%)` |
| `full-cover` | `rgba(r,g,b,opacity)` solid background covering the entire image |

Opacity is converted from the integer percentage (`0`–`100`) to a decimal (`0.0`–`1.0`) before insertion into the `rgba()` function. Hex color is parsed via `_hexToRgb()` which handles standard 6-digit hex codes.

---

### Pagination — Load More

- Initial load: `connectedCallback` calls `_loadRecords(false)` with `offset = 0`
- Load More button appears when `hasMore === true` and the initial load is complete
- Clicking the button calls `_loadRecords(true)`:
  - Sets `_isLoadingMore = true` (button label changes to "Loading…" and is disabled)
  - New records are **spread** onto the existing array: `[...this._records, ...newRecords]`
  - `_offset` is updated to `this._records.length` after merge
- The button label is controlled by the `loadMoreLabel` getter:
  - `_isLoadingMore === true` → `"Loading…"`
  - Otherwise → `"Load More"`

---

### Record Navigation

Clicking (or pressing **Enter**/**Space**) on any record navigates to its detail page via `NavigationMixin`:

```js
this[NavigationMixin.Navigate]({
    type: 'standard__recordPage',
    attributes: {
        recordId: recordId,       // from data-id attribute
        objectApiName: this.objectApiName,
        actionName: 'view'
    }
});
```

All clickable record containers have:
- `tabindex="0"` — keyboard focusable
- `data-id={record.Id}` — ID extracted via `event.currentTarget.dataset.id`
- `onkeydown={handleKeyDown}` — Enter/Space triggers navigation
- `onclick={handleRecordClick}`
- Appropriate ARIA roles (`listitem`, `button`)

---

### Carousel Controls

| Getter / Method | Purpose |
|----------------|---------|
| `_maxCarouselIndex` | `Math.max(0, totalRecords - 3)` |
| `isPrevDisabled` | `true` when `_carouselIndex <= 0` |
| `isNextDisabled` | `true` when `_carouselIndex >= _maxCarouselIndex` |
| `carouselTrackStyle` | `translateX(-N%)` where N = index × 33.33 |
| `carouselDots` | Array of `{ index, isActive, cssClass, ariaLabel }` |
| `prevSlide()` | Decrements `_carouselIndex` if > 0 |
| `nextSlide()` | Increments `_carouselIndex` if < max |
| `goToSlide(event)` | Reads `data-index` and sets `_carouselIndex` directly |

The transition uses `cubic-bezier(0.25, 0.46, 0.45, 0.94)` over `0.4s`.

On mobile (≤ 600px) each card becomes `100%` wide, effectively making it a single-card paginator.

---

## 5. Admin Properties Reference

All 22 properties are configurable in Experience Builder for the targets `lightningCommunity__Default`, `lightning__AppPage`, `lightning__RecordPage`, and `lightning__HomePage`.

### Display

| Property | Type | Default | Allowed Values | Required |
|----------|------|---------|----------------|----------|
| `componentTitle` | String | — | Any text | No |
| `displayMode` | String | `card` | `list`, `card`, `carousel`, `grid` | No |

### Data Configuration

| Property | Type | Default | Notes | Required |
|----------|------|---------|-------|----------|
| `objectApiName` | String | — | e.g. `Account`, `Grant__c` | **Yes** |
| `fieldList` | String | — | CSV of field API names | **Yes** |
| `primaryField` | String | — | Bold title field; falls back to `Name` | No |
| `imageUrlField` | String | — | Grid view only; field containing image URL | No |
| `whereClause` | String | — | SOQL WHERE body (no `WHERE` keyword) | No |
| `orderByField` | String | — | Validated against Schema.describe | No |
| `orderByDirection` | String | `ASC` | `ASC`, `DESC` | No |
| `recordsPerPage` | Integer | `10` | `1`–`200` | No |

### Theme

| Property | Type | Default | Notes |
|----------|------|---------|-------|
| `colorTheme` | String | `ocean-blue` | See 10 preset themes above |
| `accentColor` | String | — | Hex e.g. `#FF6F61`; overrides theme |
| `headerBgColor` | String | — | Hex; overrides theme |
| `cardBgColor` | String | — | Hex; overrides theme |
| `textColor` | String | — | Hex; overrides theme |

### Grid Overlay

| Property | Type | Default | Notes |
|----------|------|---------|-------|
| `overlayBgColor` | String | `#000000` | Hex color for overlay |
| `overlayTextColor` | String | `#FFFFFF` | Hex color for overlay text |
| `overlayOpacity` | Integer | `60` | `0`–`100` |
| `overlayDirection` | String | `bottom-to-top` | `bottom-to-top`, `full-cover` |

### Badges / Pills

| Property | Type | Default | Notes |
|----------|------|---------|-------|
| `badgeFields` | String | — | CSV of field API names to render as badges |
| `badgeColorMap` | String | — | `Value=#hex` pairs, comma-separated |
| `badgeStyle` | String | `filled` | `filled`, `outlined` |

---

## 6. Experience Builder Setup

### Step-by-Step

1. Open **Experience Builder** for your Experience Cloud site.
2. Navigate to the page where you want to add the component.
3. In the **Components** panel, search for **"Dynamic Record Display"**.
4. Drag the component onto the page canvas.
5. In the **Properties** panel on the right, configure at minimum:
   - **Object API Name** (required) — e.g. `Grant__c`
   - **Fields to Display (CSV)** (required) — e.g. `Name,Status__c,Award_Amount__c,Category__c`
6. Optionally configure:
   - **Primary / Title Field** — e.g. `Name`
   - **Display Mode** — choose `list`, `card`, `carousel`, or `grid`
   - **Color Theme** — select from 10 presets or enter custom hex values
   - **WHERE Clause Filter** — e.g. `Status__c = 'Active' AND IsPublic__c = true`
   - **ORDER BY Field** + **Sort Direction**
   - **Badge Fields** — e.g. `Status__c,Category__c`
7. Click **Publish** to make the page live.

### Example Configuration — Active Grants (Card View)

| Property | Value |
|----------|-------|
| Object API Name | `Grant__c` |
| Fields to Display | `Name,Status__c,Award_Amount__c,Category__c,Application_Deadline__c` |
| Primary / Title Field | `Name` |
| Display Mode | `card` |
| Color Theme | `ocean-blue` |
| WHERE Clause Filter | `Status__c = 'Active'` |
| ORDER BY Field | `Application_Deadline__c` |
| Sort Direction | `ASC` |
| Records Per Page | `9` |
| Badge Fields | `Status__c,Category__c` |
| Badge Style | `filled` |

### Example Configuration — Featured Grants (Grid View with Images)

| Property | Value |
|----------|-------|
| Object API Name | `Grant__c` |
| Fields to Display | `Name,Category__c,Award_Amount__c,Image_URL__c` |
| Primary / Title Field | `Name` |
| Image URL Field | `Image_URL__c` |
| Display Mode | `grid` |
| Color Theme | `midnight-dark` |
| WHERE Clause Filter | `IsFeatured__c = true` |
| Badge Fields | `Category__c` |
| Overlay Direction | `bottom-to-top` |
| Overlay Opacity | `70` |

---

## 7. Deployment

### Prerequisites

- Salesforce CLI (`sf`) installed
- Authenticated org alias `Hawaii-Grants-Management` (or substitute your alias)

### Deploy Command

```bash
sf project deploy start \
  --source-dir force-app/main/default/classes/DRD_RecordDisplayController.cls \
  --source-dir force-app/main/default/classes/DRD_RecordDisplayController.cls-meta.xml \
  --source-dir force-app/main/default/classes/DRD_RecordDisplayControllerTest.cls \
  --source-dir force-app/main/default/classes/DRD_RecordDisplayControllerTest.cls-meta.xml \
  --source-dir force-app/main/default/lwc/dynamicRecordDisplay \
  --target-org Hawaii-Grants-Management
```

> **Important:** Always deploy the Apex classes and the LWC **in the same transaction**. The LWC references `DRD_RecordDisplayController` at deploy-time validation; deploying the LWC alone will fail with `Unable to find Apex action class`.

### Deploy All at Once (recommended)

```bash
sf project deploy start \
  --source-dir force-app/main/default/classes \
  --source-dir force-app/main/default/lwc/dynamicRecordDisplay \
  --target-org Hawaii-Grants-Management
```

### Retrieve Latest from Org

```bash
sf project retrieve start \
  --source-dir force-app/main/default/classes/DRD_RecordDisplayController.cls \
  --source-dir force-app/main/default/lwc/dynamicRecordDisplay \
  --target-org Hawaii-Grants-Management
```

---

## 8. Test Coverage

**Test class:** `DRD_RecordDisplayControllerTest`  
**Total methods:** 21  
**Bulk test:** 251 + 12 = 263 records

### Test Method Summary

| Method | Scenario |
|--------|---------|
| `shouldReturnRecords_WhenValidObjectAndFields` | First page of 10 from 12 records; `hasMore = true` |
| `shouldReturnFieldLabels_WhenValidFields` | Labels map populated for all requested fields |
| `shouldIncludeIdInResults_WhenIdNotInFieldList` | `Id` auto-prepended even when not in `fieldList` |
| `shouldReturnAllRemainingRecords_WhenLastPage` | Offset 10 returns remaining 2; `hasMore = false` |
| `shouldRespectOrderByAsc_WhenOrderByFieldAndDirProvided` | First record name ≤ last record name |
| `shouldRespectOrderByDesc_WhenOrderByDirIsDesc` | First record name ≥ last record name |
| `shouldFilterRecords_WhenValidWhereClauseProvided` | All returned records match `Type = 'Prospect'` |
| `shouldReturnEmptyList_WhenWhereClauseMatchesNoRecords` | Zero records; `hasMore = false` |
| `shouldDefaultLimit_WhenQueryLimitIsNull` | `null` limit → returns 10 records |
| `shouldCapLimit_WhenQueryLimitExceedsMaximum` | `999` limit → capped at 200; returns all 12 available |
| `shouldHandleFieldsWithWhitespace_WhenCsvHasSpaces` | ` Name , Type , Industry ` resolved cleanly |
| `shouldReturnHasMoreFalse_WhenOnSinglePageOfResults` | Page size 50 > 12 records → `hasMore = false` |
| `shouldThrowAuraHandledException_WhenObjectApiNameIsBlank` | Blank string → "Object API name is required" |
| `shouldThrowAuraHandledException_WhenObjectApiNameIsNull` | `null` → "Object API name is required" |
| `shouldThrowAuraHandledException_WhenFieldListIsBlank` | Blank field list → "field" in message |
| `shouldThrowAuraHandledException_WhenObjectApiNameIsInvalid` | `NotARealObject__xyz` → "invalid object" |
| `shouldThrowAuraHandledException_WhenFieldNameIsInvalid` | `NotARealField__xyz` → "invalid field" |
| `shouldThrowAuraHandledException_WhenOrderByFieldIsInvalid` | Invalid ORDER BY field → "invalid order by" |
| `shouldThrowAuraHandledException_WhenWhereClauseContainsDelete` | `DELETE` in WHERE → "disallowed keyword" |
| `shouldThrowAuraHandledException_WhenWhereClauseContainsUnion` | `UNION SELECT` in WHERE → "disallowed keyword" |
| `shouldAcceptCleanWhereClause_WhenNoBlockedKeywordsPresent` | Valid `Type = 'Prospect' AND Industry = 'Technology'` succeeds |
| `shouldHandleBulkQuery_WhenManyRecordsExist` | 263 total records; page of 10 returned; `hasMore = true` |

All assertions use the `Assert` class (`Assert.areEqual`, `Assert.isTrue`, `Assert.isFalse`, `Assert.isNotNull`, `Assert.fail`).

### Running Tests

```bash
sf apex run test \
  --class-names DRD_RecordDisplayControllerTest \
  --target-org Hawaii-Grants-Management \
  --result-format human \
  --output-dir test-results \
  --wait 10
```

---

## 9. Responsive Behaviour

| Breakpoint | Card / Grid Columns | Carousel Card Width |
|------------|--------------------|--------------------|
| > 900px | 3 columns | 33.33% (3 visible) |
| 601px – 900px | 2 columns | 50% (2 visible) |
| ≤ 600px | 1 column | 100% (1 visible) |

Additional mobile adjustments at ≤ 600px:
- List rows switch to `flex-direction: column` (fields stack vertically)
- Carousel nav buttons shrink to `36×36px`
- Component title font-size reduces to `1.1rem`
- Card and grid gaps reduce to `12px` / `10px`

---

## 10. Accessibility

| Feature | Implementation |
|---------|---------------|
| Loading state | `role="status"`, `aria-label="Loading records"` |
| Error state | `role="alert"` — announced immediately by screen readers |
| Empty state | `role="status"` |
| List records | `role="list"` / `role="listitem"` |
| Card/Grid records | `role="list"` / `role="listitem"` + `aria-label={record.primaryValue}` |
| Carousel region | `role="region"` + `aria-label={carouselAriaLabel}` |
| Carousel live area | `aria-live="polite"` on the track outer wrapper |
| Carousel buttons | `aria-label="Previous slide"` / `"Next slide"` |
| Carousel dots | `role="tablist"` container; each dot is `role="tab"` with `aria-selected` + `aria-label="Go to slide N"` |
| Keyboard navigation | Enter / Space on any record container triggers navigation (same as click) |
| Spinner | `aria-hidden="true"` on the visual ring; container has `role="status"` |
| Badge spans | `title={field.displayValue}` for tooltip on truncated values |
| Focus ring | All interactive elements have `outline: none` in CSS; browsers apply default focus outlines; `tabindex="0"` ensures keyboard reach |

---

## 11. Known Constraints

| Constraint | Detail |
|------------|--------|
| **SOQL OFFSET limit** | Salesforce enforces a maximum `OFFSET` of `2000`. Load More will silently stop working if the combined offset exceeds this. For large datasets, add a WHERE clause filter or reduce scope. |
| **Governor limits** | Each page load issues one synchronous Apex call. Each "Load More" click issues an additional call. Querying many fields on large objects may approach heap limits — keep `fieldList` to 6 or fewer fields for best performance. |
| **`@AuraEnabled(cacheable=true)`** | The Apex method is cached. Changing the configuration in Experience Builder and re-publishing will serve cached results until the cache expires (typically 15 minutes) or the page is hard-refreshed. For real-time data requirements, consider removing `cacheable=true`. |
| **`without sharing`** | All records of the queried object visible to the org are returned, subject only to the WHERE clause filter. Ensure the guest user profile on the Experience Cloud site does not have access to sensitive objects, or add appropriate WHERE filters. |
| **Relationship fields** | Dot-notation relationship fields (e.g. `Account.Name`) are not supported. Only fields directly on the queried object may be listed in `fieldList`. |
| **Image URLs** | The `imageUrlField` value is used as a CSS `background-image: url(...)`. Images must be publicly accessible (e.g. Salesforce Files with public sharing, or external URLs). Relative Salesforce resource paths will not resolve in community context. |
| **`color-mix()` support** | The CSS `color-mix()` function used for alternating list rows requires a modern browser (Chrome 111+, Firefox 113+, Safari 16.2+). Older browsers will fall back to the base card background color for even rows. |
| **`lightningCommunity__Page` target** | This target was intentionally excluded from `<targetConfig>` because it does not support `<property>` elements. The component is still fully functional on community pages — it just cannot expose its property panel for that specific target type. Use `lightningCommunity__Default` pages to configure properties in Experience Builder. |
| **Carousel on < 3 records** | With fewer than 3 records, `_maxCarouselIndex = 0`, both nav buttons are disabled, and a single dot is shown. The carousel is effectively static. |
| **Badge field values** | Only non-empty field values are rendered as badges. Empty strings and `null` values fall through to plain text display (showing an em-dash `—`). |

---

*Documentation generated for dynamicRecordDisplay v1.0.0 — deployed to Hawaii-Grants-Management (API v66.0)*

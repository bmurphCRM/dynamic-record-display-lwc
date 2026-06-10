import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getRecords from '@salesforce/apex/DRD_RecordDisplayController.getRecords';

// ─── Long-text field types that should render full-width below inline columns ──
const LONG_TEXT_TYPES = new Set(['textarea', 'richtextarea', 'longtextarea', 'encryptedstring']);

// ─── Badge Auto-Color Palette (12 distinct accessible colors) ─────────────────
const BADGE_AUTO_COLORS = [
    { bg: '#0070D2', text: '#FFFFFF' },
    { bg: '#2E7D32', text: '#FFFFFF' },
    { bg: '#E65100', text: '#FFFFFF' },
    { bg: '#7B1FA2', text: '#FFFFFF' },
    { bg: '#C2185B', text: '#FFFFFF' },
    { bg: '#00796B', text: '#FFFFFF' },
    { bg: '#546E7A', text: '#FFFFFF' },
    { bg: '#F57F17', text: '#1A1A1A' },
    { bg: '#4527A0', text: '#FFFFFF' },
    { bg: '#AD1457', text: '#FFFFFF' },
    { bg: '#00838F', text: '#FFFFFF' },
    { bg: '#558B2F', text: '#FFFFFF' }
];

const CAROUSEL_VISIBLE_COUNT = 3;

/**
 * Dynamic Record Display LWC
 * Renders records from any Salesforce object in four configurable display modes:
 * list, card, carousel, or image-overlay grid. Fully themeable via preset
 * themes and custom hex color overrides.
 */
export default class DynamicRecordDisplay extends NavigationMixin(LightningElement) {

    // ── Data Configuration (@api) ──────────────────────────────────────────────

    /** API name of the Salesforce object to query (e.g. 'Account', 'Grant__c'). */
    @api objectApiName;

    /** Comma-separated list of field API names to display (e.g. 'Name,Status__c'). */
    @api fieldList;

    /** API name of the field to use as the primary/title of each record. */
    @api primaryField;

    /** API name of the field containing the image URL (grid view only). */
    @api imageUrlField;

    /** Optional SOQL WHERE clause body (admin-configured, not user input). */
    @api whereClause;

    /** Field API name to sort results by. */
    @api orderByField;

    /** Sort direction: 'ASC' or 'DESC'. */
    @api orderByDirection = 'ASC';

    /** Number of records per page (loaded in increments). */
    @api recordsPerPage = 10;

    // ── Display Configuration (@api) ──────────────────────────────────────────

    /** Optional heading displayed above the records. */
    @api componentTitle;

    /** Display mode: 'list' | 'card' | 'carousel' | 'grid'. */
    @api displayMode = 'card';

    // ── Theme Configuration (@api) ────────────────────────────────────────────

    /** Preset color theme name. */
    @api colorTheme = 'ocean-blue';

    /** Custom hex code for accent color (overrides theme). */
    @api accentColor;

    /** Custom hex code for header/title background (overrides theme). */
    @api headerBgColor;

    /** Custom hex code for card background (overrides theme). */
    @api cardBgColor;

    /** Custom hex code for body text (overrides theme). */
    @api textColor;

    // ── Grid Overlay (@api) ───────────────────────────────────────────────────

    /** Hex code for overlay background color. */
    @api overlayBgColor = '#000000';

    /** Hex code for overlay text color. */
    @api overlayTextColor = '#FFFFFF';

    /** Overlay opacity percentage (0–100). */
    @api overlayOpacity = 60;

    /** Overlay direction: 'bottom-to-top' (gradient) | 'full-cover' (solid). */
    @api overlayDirection = 'bottom-to-top';

    // ── Badge Configuration (@api) ────────────────────────────────────────────

    /** Comma-separated field API names to render as colored badge pills. */
    @api badgeFields;

    /**
     * Optional value-to-color override map for badges.
     * Format: 'Active=#2E7D32,Closed=#C2185B,Pending=#E65100'
     */
    @api badgeColorMap;

    /** Badge style: 'filled' (solid bg + white text) | 'outlined' (colored border). */
    @api badgeStyle = 'filled';

    // ── Internal Tracked State ────────────────────────────────────────────────

    @track _records = [];
    @track _fieldLabels = {};
    @track _fieldTypes = {};
    @track _hasMore = false;
    @track _isLoading = false;
    @track _isLoadingMore = false;
    @track _errorMessage = null;
    @track _offset = 0;
    @track _carouselIndex = 0;

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        this._loadRecords(false);
    }

    // ── Data Fetching ─────────────────────────────────────────────────────────

    _loadRecords(isLoadMore) {
        if (!this.objectApiName || !this.fieldList) {
            return;
        }

        if (isLoadMore) {
            this._isLoadingMore = true;
        } else {
            this._isLoading = true;
            this._records = [];
            this._offset = 0;
            this._carouselIndex = 0;
        }
        this._errorMessage = null;

        const pageLimit = parseInt(this.recordsPerPage, 10) || 10;

        // Auto-include imageUrlField in the query if it isn't already listed,
        // so the grid view works even when the admin only sets Image URL Field
        // without also adding it to the Field List CSV.
        let effectiveFieldList = this.fieldList;
        if (this.imageUrlField) {
            const existing = effectiveFieldList
                .split(',')
                .map(f => f.trim().toLowerCase());
            if (!existing.includes(this.imageUrlField.trim().toLowerCase())) {
                effectiveFieldList = effectiveFieldList + ',' + this.imageUrlField.trim();
            }
        }

        getRecords({
            objectApiName: this.objectApiName,
            fieldListCsv: effectiveFieldList,
            whereClause: this.whereClause || null,
            orderByField: this.orderByField || null,
            orderByDir: this.orderByDirection || 'ASC',
            queryLimit: pageLimit,
            queryOffset: isLoadMore ? this._offset : 0
        })
        .then(result => {
            if (result) {
                const newRecords = result.records || [];
                this._records = isLoadMore
                    ? [...this._records, ...newRecords]
                    : newRecords;
                this._fieldLabels = result.fieldLabels || {};
                this._fieldTypes = result.fieldTypes || {};
                this._hasMore = result.hasMore === true;
                this._offset = this._records.length;
            }
        })
        .catch(error => {
            const msg = error && error.body && error.body.message
                ? error.body.message
                : (error && error.message ? error.message : 'An unexpected error occurred.');
            this._errorMessage = msg;
        })
        .finally(() => {
            this._isLoading = false;
            this._isLoadingMore = false;
        });
    }

    // ── Event Handlers ────────────────────────────────────────────────────────

    handleLoadMore() {
        if (!this._isLoadingMore) {
            this._loadRecords(true);
        }
    }

    handleRecordClick(event) {
        const recordId = event.currentTarget.dataset.id;
        if (!recordId || !this.objectApiName) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: this.objectApiName,
                actionName: 'view'
            }
        });
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleRecordClick(event);
        }
    }

    // ── Carousel Handlers ─────────────────────────────────────────────────────

    prevSlide() {
        if (this._carouselIndex > 0) {
            this._carouselIndex -= 1;
        }
    }

    nextSlide() {
        if (this._carouselIndex < this._maxCarouselIndex) {
            this._carouselIndex += 1;
        }
    }

    goToSlide(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        if (!Number.isNaN(idx) && idx >= 0 && idx <= this._maxCarouselIndex) {
            this._carouselIndex = idx;
        }
    }

    // ── State Getters ─────────────────────────────────────────────────────────

    get isLoading() { return this._isLoading; }
    get isLoadingMore() { return this._isLoadingMore; }
    get hasError() { return !!this._errorMessage; }
    get errorMessage() { return this._errorMessage; }
    get hasTitle() { return !!this.componentTitle; }

    get showEmpty() {
        return !this._isLoading && !this._errorMessage && this._records.length === 0;
    }

    get showRecords() {
        return !this._isLoading && !this._errorMessage && this._records.length > 0;
    }

    get showLoadMore() {
        return this._hasMore && !this._isLoading;
    }

    get loadMoreLabel() {
        return this._isLoadingMore ? 'Loading...' : 'Load More';
    }

    // ── Display Mode Getters ──────────────────────────────────────────────────

    get isListMode()     { return this.displayMode === 'list';     }
    get isCardMode() { return this.displayMode === 'card'; }
    get isCarouselMode() { return this.displayMode === 'carousel'; }
    get isGridMode() { return this.displayMode === 'grid'; }

    // ── List View Column Layout ───────────────────────────────────────────────

    /**
     * Returns the number of "inline" (non-long-text) fields that will render
     * as grid columns in the list view. Used to build a consistent column
     * template across all rows.
     */
    get _inlineFieldCount() {
        return (this.fieldList || '')
            .split(',')
            .map(f => f.trim())
            .filter(f => f && this._fieldLabels[f])
            .filter(f => !LONG_TEXT_TYPES.has((this._fieldTypes[f] || '').toLowerCase()))
            .length;
    }

    /**
     * Inline style applied to `.drd-list-view` so every row's CSS grid
     * shares an identical column template — the first column gets 2fr
     * (typically the Name / primary field) and every subsequent column
     * gets 1fr.  A fallback of `repeat(auto-fit, minmax(150px, 1fr))` is
     * used while field metadata is still loading.
     */
    get listViewStyle() {
        const count = this._inlineFieldCount;
        if (count <= 0) return '';
        const cols = count === 1
            ? '1fr'
            : `2fr ${Array(count - 1).fill('1fr').join(' ')}`;
        return `--drd-list-col-template: ${cols};`;
    }

    // ── Theme / Styling Getters ───────────────────────────────────────────────

    get containerClass() {
        const theme = (this.colorTheme || 'ocean-blue')
            .toLowerCase().replace(/\s+/g, '-');
        return `drd-container drd-theme-${theme}`;
    }

    get containerStyle() {
        const parts = [];
        if (this.accentColor) parts.push(`--drd-accent: ${this.accentColor}`);
        if (this.headerBgColor) parts.push(`--drd-header-bg: ${this.headerBgColor}`);
        if (this.cardBgColor) parts.push(`--drd-card-bg: ${this.cardBgColor}`);
        if (this.textColor) parts.push(`--drd-text: ${this.textColor}`);
        return parts.length > 0 ? parts.join('; ') + ';' : '';
    }

    get overlayTextStyle() {
        return `color: ${this.overlayTextColor || '#FFFFFF'};`;
    }

    // ── Carousel Getters ──────────────────────────────────────────────────────

    get _maxCarouselIndex() {
        const total = this._records.length;
        return Math.max(0, total - CAROUSEL_VISIBLE_COUNT);
    }

    get isPrevDisabled() { return this._carouselIndex <= 0; }

    get isNextDisabled() {
        return this._carouselIndex >= this._maxCarouselIndex;
    }

    get carouselTrackStyle() {
        const offset = this._carouselIndex * (100 / CAROUSEL_VISIBLE_COUNT);
        return `transform: translateX(-${offset}%); transition: transform 0.4s cubic-bezier(0.25, 0.46, 0.45, 0.94);`;
    }

    get carouselAriaLabel() {
        return this.componentTitle
            ? `${this.componentTitle} carousel`
            : 'Record carousel';
    }

    get carouselDots() {
        const totalDots = Math.max(1, this._maxCarouselIndex + 1);
        return Array.from({ length: totalDots }, (_, i) => ({
            index: i,
            isActive: i === this._carouselIndex,
            cssClass: i === this._carouselIndex
                ? 'drd-dot drd-dot-active'
                : 'drd-dot',
            ariaLabel: `Go to slide ${i + 1}`
        }));
    }

    // ── Badge Helpers ─────────────────────────────────────────────────────────

    get _badgeFieldSet() {
        if (!this.badgeFields) return new Set();
        return new Set(
            this.badgeFields.split(',')
                .map(f => f.trim().toLowerCase())
                .filter(f => f)
        );
    }

    _parseBadgeColorMap() {
        const map = {};
        if (!this.badgeColorMap) return map;
        this.badgeColorMap.split(',').forEach(pair => {
            const eqIdx = pair.indexOf('=');
            if (eqIdx > 0) {
                const key = pair.substring(0, eqIdx).trim().toLowerCase();
                const val = pair.substring(eqIdx + 1).trim();
                if (key && val) map[key] = val;
            }
        });
        return map;
    }

    _hashColor(value) {
        const str = String(value || '').toLowerCase();
        let hash = 0;
        for (let i = 0; i < str.length; i++) {
            hash = ((hash * 31) + str.charCodeAt(i)) & 0x7fffffff;
        }
        return BADGE_AUTO_COLORS[hash % BADGE_AUTO_COLORS.length];
    }

    _buildBadgeStyle(displayValue, colorMapOverride) {
        const key = String(displayValue || '').toLowerCase();
        let bgColor, textColor;

        if (colorMapOverride[key]) {
            bgColor = colorMapOverride[key];
            // Determine contrast: if the override looks light, use dark text
            textColor = this._isLightColor(bgColor) ? '#1A1A1A' : '#FFFFFF';
        } else {
            const auto = this._hashColor(displayValue);
            bgColor = auto.bg;
            textColor = auto.text;
        }

        if (this.badgeStyle === 'outlined') {
            return `border: 2px solid ${bgColor}; color: ${bgColor}; background-color: transparent; border-radius: 12px; padding: 2px 10px; font-size: 0.75rem; font-weight: 600; display: inline-flex; align-items: center;`;
        }
        return `background-color: ${bgColor}; color: ${textColor}; border-radius: 12px; padding: 2px 10px; font-size: 0.75rem; font-weight: 600; display: inline-flex; align-items: center;`;
    }

    _isLightColor(hex) {
        try {
            const { r, g, b } = this._hexToRgb(hex);
            // Relative luminance formula
            const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
            return luminance > 0.6;
        } catch (_) {
            return false;
        }
    }

    // ── Field Value Formatter ─────────────────────────────────────────────────

    /**
     * Formats a raw Salesforce field value according to its display type.
     * @param {*}      rawValue  - The raw value from the record.
     * @param {string} fieldType - The Apex Schema.DisplayType string (e.g. 'Currency').
     * @returns {string} Formatted display string.
     */
    _formatFieldValue(rawValue, fieldType) {
        if (rawValue === null || rawValue === undefined || rawValue === '') return '';

        const type = (fieldType || '').toLowerCase();

        try {
            switch (type) {
                case 'currency':
                    return new Intl.NumberFormat('en-US', {
                        style: 'currency',
                        currency: 'USD',
                        minimumFractionDigits: 2,
                        maximumFractionDigits: 2
                    }).format(Number(rawValue));

                case 'percent':
                    // Salesforce stores percent as the face number (15 = 15%)
                    return new Intl.NumberFormat('en-US', {
                        minimumFractionDigits: 0,
                        maximumFractionDigits: 4
                    }).format(Number(rawValue)) + '%';

                case 'date': {
                    // Salesforce returns dates as 'YYYY-MM-DD' strings
                    const parts = String(rawValue).split('-');
                    return new Intl.DateTimeFormat('en-US', {
                        year: 'numeric',
                        month: 'short',
                        day: 'numeric',
                        timeZone: 'UTC'
                    }).format(new Date(Date.UTC(
                        parseInt(parts[0], 10),
                        parseInt(parts[1], 10) - 1,
                        parseInt(parts[2], 10)
                    )));
                }

                case 'datetime':
                    return new Intl.DateTimeFormat('en-US', {
                        year: 'numeric',
                        month: 'short',
                        day: 'numeric',
                        hour: '2-digit',
                        minute: '2-digit'
                    }).format(new Date(rawValue));

                case 'integer':
                case 'long':
                    return new Intl.NumberFormat('en-US', {
                        maximumFractionDigits: 0
                    }).format(Number(rawValue));

                case 'double':
                    return new Intl.NumberFormat('en-US', {
                        minimumFractionDigits: 0,
                        maximumFractionDigits: 2
                    }).format(Number(rawValue));

                default:
                    return String(rawValue);
            }
        } catch (_) {
            return String(rawValue);
        }
    }

    // ── Grid Overlay Helpers ──────────────────────────────────────────────────

    _hexToRgb(hex) {
        const clean = (hex || '#000000').replace('#', '').padEnd(6, '0');
        return {
            r: parseInt(clean.substring(0, 2), 16) || 0,
            g: parseInt(clean.substring(2, 4), 16) || 0,
            b: parseInt(clean.substring(4, 6), 16) || 0
        };
    }

    _buildOverlayStyle() {
        const rawOpacity = parseInt(this.overlayOpacity, 10);
        const opacity = Number.isNaN(rawOpacity)
            ? 0.6
            : Math.min(1, Math.max(0, rawOpacity / 100));
        const { r, g, b } = this._hexToRgb(this.overlayBgColor || '#000000');
        const rgba = `rgba(${r}, ${g}, ${b}, ${opacity})`;

        if (this.overlayDirection === 'full-cover') {
            return `background: ${rgba};`;
        }
        return `background: linear-gradient(to top, ${rgba} 0%, rgba(${r}, ${g}, ${b}, 0) 100%);`;
    }

    // ── Processed Records Getter ──────────────────────────────────────────────

    get processedRecords() {
        if (!this._records || this._records.length === 0) return [];

        const badgeSet = this._badgeFieldSet;
        const colorMapOverride = this._parseBadgeColorMap();
        const overlayStyle = this._buildOverlayStyle();

        // Maintain field order from the fieldList prop
        const orderedFieldNames = (this.fieldList || '')
            .split(',')
            .map(f => f.trim())
            .filter(f => f && this._fieldLabels[f]);

        return this._records.map(record => {
            // Build field descriptors for all configured fields
            const allFields = orderedFieldNames.map(fieldName => {
                const label = this._fieldLabels[fieldName] || fieldName;
                const rawValue = record[fieldName];
                const fieldType = this._fieldTypes[fieldName] || '';
                const displayValue = rawValue !== null && rawValue !== undefined
                    ? this._formatFieldValue(rawValue, fieldType)
                    : '';
                const isBadge = badgeSet.has(fieldName.toLowerCase()) && displayValue !== '';

                return {
                    name: fieldName,
                    label: label,
                    displayValue: displayValue || '\u2014',
                    isBadge: isBadge,
                    isNotBadge: !isBadge,
                    badgeStyle: isBadge
                        ? this._buildBadgeStyle(displayValue, colorMapOverride)
                        : ''
                };
            });

            // Resolve primary field value
            const primaryFieldName = this.primaryField;
            let primaryValue = '';
            if (primaryFieldName && record[primaryFieldName] != null) {
                primaryValue = String(record[primaryFieldName]);
            } else if (record['Name'] != null) {
                primaryValue = String(record['Name']);
            } else {
                primaryValue = 'Untitled';
            }

            // Secondary fields exclude the primary field
            const secondaryFields = primaryFieldName
                ? allFields.filter(f => f.name !== primaryFieldName)
                : allFields;

            // Split fields into inline columns vs full-width long-text rows
            const inlineFields    = allFields.filter(f => !LONG_TEXT_TYPES.has((this._fieldTypes[f.name] || '').toLowerCase()));
            const longTextFields  = allFields.filter(f =>  LONG_TEXT_TYPES.has((this._fieldTypes[f.name] || '').toLowerCase()));

            // Badge-only fields for grid view overlay
            const badgeOnlyFields = allFields.filter(f => f.isBadge);

            // Image URL for grid view
            const imageUrl = this.imageUrlField && record[this.imageUrlField]
                ? String(record[this.imageUrlField])
                : '';

            const gridItemStyle = imageUrl
                ? `background-image: url('${imageUrl}'); background-size: cover; background-position: center;`
                : `background: var(--drd-accent, #0070D2);`;

            return {
                Id: record['Id'] || '',
                primaryValue: primaryValue,
                fields: allFields,
                secondaryFields: secondaryFields,
                inlineFields: inlineFields,
                longTextFields: longTextFields,
                hasLongTextFields: longTextFields.length > 0,
                badgeOnlyFields: badgeOnlyFields,
                hasBadgeFields: badgeOnlyFields.length > 0,
                gridItemStyle: gridItemStyle,
                overlayStyle: overlayStyle
            };
        });
    }
}
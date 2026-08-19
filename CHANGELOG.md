# Clearance Changelog

## v0.6.0 (2026-08-20)

### Validators
* Added generic `Validator` config to support configurable validator instances.
* Refactored `ValidatorLink` to support validator network connections and SRID propagation.
* Added `Duplicate` validator to detect duplicate OSM objects within a project, with dedicated SQL queries.
* Added `Network` validator to validate objects against a network topology (neighbor relationships), with dedicated SQL queries.
* Added `specific_osm_tags_matches` to filter OSM tag matches per validator.

### Bug Fixes
* Changeset user is now nullable to handle incomplete OSM data.

---

## v0.5.5 (2026-08-15)

### Validator Architecture Refactoring
* Split `Validator` class into `Validator` and `ValidatorLink` for clearer separation of concerns.
* Moved apply logic into validator classes.
* Added base connection handling to validators.
* Split `time_machine_validate` loop to iterate first on validators.

### New Validators
* Added `ChangesetComment` validator to check changeset comments.
* Added `ChangesetReviewRequested` validator to check review request tags.

### Changeset Improvements
* Updated changeset processing on a log bias.
* Added changeset update timestamp migration.

### Performance
* Fixed `changes_logs()` SQL query performance (major rewrite of changes_logs.sql).

### Compatibility
* Added `ostruct` gem for Ruby 4.0 compatibility.

### Maintenance
* Reviewed template config.
* Lint: replaced `File.new().read` with `File.read`.

---

## v0.5.4 (2026-08-11)

### LoCha & Semantic Grouping
* Project count now reflects locha subgroups.
* Use `semantic_group` id in place of link group index for consistency.

### Dependencies
* Updated `openstreetmap_logical_history` library, fixing geom_score calculation.

---

## v0.5.3 (2026-07-10)

### Dependencies
* Updated `overpass_parser_ruby` to fix set aggregation issue.

---

## v0.5.2 (2026-07-08)

### Validation
* Cleaned validation jsonb content for consistency.
* Fixed changeset bbox field name.

### Code Quality
* Added custom Rubocop rule (`FromHashStrict`) to ensure `from_hash` is always called with the strict option.
* Applied `from_hash` strict option across the codebase.

### Database
* Added migration to clean validation log jsonb content.
* Added migration to fix changeset bbox column structure.

---

## v0.5.1 (2026-07-02)

### Bug Fixes
* Fixed `osm_diff_tags` filter.

### Performance
* Optimized `schema-check-integrity` SQL queries.
* Performance optimization on update geometry trigger.

### Configuration
* Added missing `NUXT_PUBLIC_MAP_STYLE_URL` to frontend environment.

### Testing
* Enabled integrity checks in test suite.

### Maintenance
* Bundle update.
* Lint cleanup.

---

## From v0.4 to v0.5

This development cycle delivers a major overhaul of Clearance's core processing engine, validation workflow, and database architecture. The primary focus was improving LoCha generation, scalability, validation quality, and operational reliability.

## Major Features

### LoCha Engine Redesign
* Introduced stable `locha_id` storage and computation.
* Switched to connected-component based clustering.
* Added recursive splitting for oversized clusters.
* Improved propagation of related objects and references.
* Added semantic grouping support for logical changes.
* Improved cluster accuracy and consistency.

### Validation Improvements
* Added `Delayed` validator. Do not synchronise hot changes. Accept cold changes automaticaly.
* Added `GeomInvalid` validator.
* Improved geometry scoring and validation logic.
* Refactored validation execution and propagation.
* Added semantic validation groups.
* Improved validation logging and indexing.

### OpenAPI Support
* Added OpenAPI specification generation.
* Added API output validation.

## Database & Performance

### Database Changes
* Upgraded stack to PostgreSQL 18 and PostGIS 3.6.
* Added integrity checking., improved foreign-key and reference handling.

### Geometry Processing
* Migrated toward computed/generated geometry columns.
* Improved geometry propagation and equality checks.

### Performance
* Optimized LoCha generation.
* Improved connected-component processing.
* Reduced memory consumption during updates.
* Simplified several recursive SQL workflows.

## OSM Logical History Integration

Large portions of internal logic were replaced by the shared `openstreetmap_logical_history` library, including:
* Conflation
* Geometry handling
* Tag comparison
* Distance calculations
* OSM object abstractions

## Import / Export

* Improved update ingestion pipeline.
* Better handling of deleted objects.
* Improved relation geometry processing.
* Added retained diff and export improvements.
* Improved Atom feed generation and export logging.

## Operations & Deployment

### Docker
* Simplified container architecture.
* Added health checks.
* Improved Docker Compose configuration.
* Added configurable PostgreSQL/PostGIS versions.

### Integrity Tooling
Added integrity verification tooling to ensure retained exports remain consistent with imported updates.

### Configuration
* Separate config and data paths.
* Safer configuration validation.

## Developer Experience
* Upgraded to Ruby 3.4.
* Improved CI/CD pipelines.
* Added GitHub image publishing.
* Expanded Sorbet typing coverage.
* Improved test and build performance.

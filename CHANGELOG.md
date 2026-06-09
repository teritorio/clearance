# Clearance Changelog

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

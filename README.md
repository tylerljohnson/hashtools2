# hashtools2

A comprehensive file deduplication and management system built in Java. Hashtools2 provides utilities for working with file digests, metadata validation, and duplicate file management through a combination of Java tools and shell scripts integrated with PostgreSQL.

## Features

- Generate hash-based metadata files for directories or files
- Validate existing metadata files
- Identify and manage duplicate files across storage locations
- Track primary (original) and redundant (duplicate) copies
- Special handling for media files (images, videos, audio)
- Database-backed file tracking and analysis
- Safe file management operations

## Getting Started

### Prerequisites

- Java 21 or higher
- Maven (for building from source)

#### Main dependencies
- [Picocli 4.7.7](https://picocli.info/) (command-line parsing)
- [Apache Tika 3.0.0](https://tika.apache.org/) (MIME-type detection)
- [SLF4J 2.0.7](https://www.slf4j.org/) (logging)

### Building

To build the project, run:

```
mvn clean package
```

The resulting JAR will be located at `target/hashtools2.jar`.

## Usage

### Java CLI Tool

Run the core Java tool with:
```bash
java -jar target/hashtools2.jar [command] [options]
```

Example commands:
```bash
# Generate a metadata file
java -jar target/hashtools2.jar generate [directory] --output=output.hashes

# Validate a metadata file
java -jar target/hashtools2.jar meta validate [options]
```

For detailed Java tool usage:
```bash
java -jar hashtools2.jar --help
```

### File Management Workflow

1. **Generate Hashes**
   ```bash
   ./bin/gen-hashes.bash       # Edit script to specify directories
   ```

2. **Load Into Database**
   ```bash
   ./bin/load_hashes.bash path/to/output.hashes
   ```

3. **Check for Duplicates**
   ```bash
   ./bin/check-vault-outdated.bash [--vault-base PATH] [--format tsv|json]
   ```

4. **Remove Redundant Files**
   ```bash
   # Dry run first
   ./bin/remove_redundant_files.bash
   
   # Actually remove files and update database
   ./bin/remove_redundant_files.bash --force --sync-db
   ```

### Database Configuration

Default connection settings (override with environment variables):
- Host: cooper
- Database: tyler
- User: tyler
- Port: 5432

Environment variables:
- `PGHOST`
- `PGUSER`
- `PGDATABASE`
- `PGPORT`

## Output File Format

The generated metadata file is a tab-separated values (TSV) file with the following columns:

| Column Name   | Type   | Description                                       |
|---------------|--------|---------------------------------------------------|
| hash          | String | SHA1 Hash digest (algorithm depends on options)   |
| lastModified  | String | File last modified timestamp, yyyy-MM-ddThh:mm:ss |
| size          | Long   | File size in bytes                                |
| mimeType      | String | MIME type of the file                             |
| basePath      | String | Full path to the base directory                   |
| fileName      | String | Relative path (from the basePath) of the file     |

## System Components

### Java Application
- `src/main/java/hashtools/` - Main Java source code
  - `commands/` - CLI command implementations
  - `models/` - Data models
  - `processors/` - Core processing logic
  - `utils/` - Utility classes
- `src/main/resources/` - Resource files
- `src/test/java/` - Unit tests

### Database Structure

#### Core Table
The `hashes` table stores file metadata and hashes:
- `id`: Primary key (BIGSERIAL)
- `hash`: SHA-1 hex (40 characters)
- `mime_type`: File type
- `last_modified`: Timestamp
- `file_size`: Size in bytes
- `base_path`: Base directory path
- `file_path`: Relative path from base
- `full_path`: Generated column (base_path + file_path)

#### Views
Organized in three categories per file type:
- `<type>`: All files of the type
- `<type>_primary`: Original files
- `<type>_redundant`: Duplicate files

Available views:
- `files/*`: All file types
- `media/*`: All media files (images, videos, audio)
- `images/*`: Image files only
- `videos/*`: Video files only
- `audio/*`: Audio files only

### Shell Scripts
Located in the `bin/` directory:
- `gen-hashes.bash`: Generates hash files for directories
- `load_hashes.bash`: Loads hash files into PostgreSQL
- `check-vault-outdated.bash`: Identifies redundant vault files
- `remove_redundant_files.bash`: Safely removes duplicates
- `safe-move.bash`: Moves files while preserving metadata
- `truncate_hashes.bash`: Resets the database

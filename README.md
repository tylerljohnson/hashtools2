# hashtools2

A command-line tool for generating and validating hash-based metadata files. Built in Java, hashtools2 provides utilities for working with file digests, manifest files, and metadata validation.

## Features

- Generate hash-based metadata files for directories or files
- Validate existing metadata files
- Supports multiple hash algorithms
- Extensible command structure

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

Run the CLI tool with:

```
java -jar target/hashtools2.jar [command] [options]
```

### Example Commands

- Generate a metadata file:
  ```
  java -jar target/hashtools2.jar generate [options]
  ```
- Validate a metadata file:
  ```
  java -jar target/hashtools2.jar meta validate [options]
  ```

For detailed command usage, run:

```
java -jar hashtools2.jar --help
```

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

## Project Structure

- `src/main/java/hashtools/` - Main Java source code
  - `commands/` - CLI command implementations
  - `models/` - Data models
  - `processors/` - Core processing logic
  - `utils/` - Utility classes
- `src/main/resources/` - Resource files
- `src/test/java/` - Unit tests

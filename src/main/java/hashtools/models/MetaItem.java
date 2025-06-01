package hashtools.models;

// Represents metadata for a file, including its hash, last modified time, size, MIME type, base path and file path.
public record MetaItem(
        String hash,
        String lastModified,
        long fileSize,
        String mimeType,
        String basePath,
        String filePath
) {
}

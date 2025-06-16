package hashtools.utils;

public class SizeUtils {
    /**
     * Converts a size in bytes to a human-readable string, using 1024 as the unit base.
     * Examples:  512     → "512 B"
     *            2048    → "2.0 KB"
     *            5_242_880 → "5.0 MB"
     */
    public static String humanReadable(long bytes) {
        if (bytes < 1024) {
            return bytes + " B";
        }
        int unit = 1024;
        String[] units = { "KB", "MB", "GB", "TB", "PB", "EB" };
        int exp = (int) (Math.log(bytes) / Math.log(unit));
        String prefix = units[exp - 1];
        double value = bytes / Math.pow(unit, exp);
        return String.format("%.3f %s", value, prefix);
    }
}

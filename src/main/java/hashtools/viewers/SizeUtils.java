package hashtools.viewers;

public class SizeUtils {
    public static String humanReadable(long bytes) {
        if (bytes < 1024) return bytes + " B";
        int unit = 1024;
        String[] units = {"KB", "MB", "GB", "TB", "PB", "EB"};
        int exp = (int) (Math.log(bytes) / Math.log(unit));
        String pre = units[exp - 1];
        return String.format("%.3f %s", bytes / Math.pow(unit, exp), pre);
    }
}

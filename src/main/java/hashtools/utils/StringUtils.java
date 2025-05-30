package hashtools.utils;

public class StringUtils {
    private StringUtils() {}

    public static String getOrDefault(String value, String def) {
        return value != null ? value : def;
    }
}

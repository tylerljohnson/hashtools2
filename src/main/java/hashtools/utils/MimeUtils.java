package hashtools.utils;

public class MimeUtils {

    // extract the major mime type from a mime string
    public static String getMajorType(String mimeType) {
        if (mimeType == null || mimeType.isBlank()) return "";
        int slash = mimeType.indexOf('/');
        return slash > 0 ? mimeType.substring(0, slash) : mimeType;
    }

    public static boolean isImage(String mimeType) {
        if (mimeType == null) return false;
        return mimeType.toLowerCase().startsWith("image/");
    }

}

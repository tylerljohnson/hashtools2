package hashtools.utils;

import java.io.*;
import java.nio.file.*;
import java.security.*;

public final class DigestUtils {

    private static final int BUFFER_SIZE = 16 * 1024; // 16 KB
    private static final String HASH_ALGORITHM = "SHA-1";
    private static final char[] HEX_DIGITS = "0123456789abcdef".toCharArray();

    private static final ThreadLocal<MessageDigest> THREAD_DIGEST =
            ThreadLocal.withInitial(() -> {
                try {
                    return MessageDigest.getInstance(HASH_ALGORITHM);
                } catch (NoSuchAlgorithmException e) {
                    throw new IllegalStateException(HASH_ALGORITHM + " not available", e);
                }
            });

    private DigestUtils() {}

    public static String hash(Path file) throws IOException {
        MessageDigest md = THREAD_DIGEST.get();
        md.reset();

        try (InputStream in = Files.newInputStream(file)) {
            byte[] buffer = new byte[BUFFER_SIZE];
            int bytesRead;
            while ((bytesRead = in.read(buffer)) != -1) {
                md.update(buffer, 0, bytesRead);
            }
        }

        return toHex(md.digest());
    }

    private static String toHex(byte[] bytes) {
        char[] chars = new char[bytes.length * 2];
        for (int i = 0; i < bytes.length; i++) {
            int b = bytes[i] & 0xFF;
            chars[i * 2]     = HEX_DIGITS[b >>> 4];
            chars[i * 2 + 1] = HEX_DIGITS[b & 0x0F];
        }
        return new String(chars);
    }

}

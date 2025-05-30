package hashtools.utils;

import picocli.CommandLine.*;

import java.io.*;
import java.util.jar.*;

public class ManifestVersionProvider implements IVersionProvider {
    @Override
    public String[] getVersion() throws Exception {
        try (InputStream is = getClass().getResourceAsStream("/META-INF/MANIFEST.MF")) {
            if (is == null) {
                return new String[] { "Version information not available" };
            }
            Manifest manifest = new Manifest(is);
            var attrs = manifest.getMainAttributes();
            String title = StringUtils.getOrDefault(attrs.getValue("Implementation-Title"), "Unknown Title");
            String version = StringUtils.getOrDefault(attrs.getValue("Implementation-Version"), "unknown-version");
            String artifact = StringUtils.getOrDefault(attrs.getValue("Implementation-Vendor-Id"), "unknown-artifact");
            String timestamp = StringUtils.getOrDefault(attrs.getValue("Build-Timestamp"), "unknown-timestamp");

            return new String[] {
                    String.format("%s (%s) version %s", title, artifact, version),
                    String.format("Built on: %s", timestamp),
            };
        }
    }

}
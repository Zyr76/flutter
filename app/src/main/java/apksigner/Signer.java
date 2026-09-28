package apksigner;

import android.content.res.AssetManager;

import com.androlua.LuaApplication;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.security.spec.PKCS8EncodedKeySpec;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

public final class Signer {
    private static final String CERT_ASSET_PATH = "keys/testkey.x509.pem";
    private static final String KEY_ASSET_PATH = "keys/testkey.pk8";

    private Signer() {
    }

    public static void sign(String inputApkPath, String outputApkPath) throws Exception {
        if (inputApkPath == null || outputApkPath == null) {
            throw new IllegalArgumentException("input/output path must not be null");
        }
        File inputApk = new File(inputApkPath);
        if (!inputApk.isFile()) {
            throw new IOException("Input APK not found: " + inputApkPath);
        }
        File outputApk = new File(outputApkPath);
        if (inputApk.getAbsolutePath().equals(outputApk.getAbsolutePath())) {
            throw new IllegalArgumentException("Input and output APK paths must be different");
        }
        File parent = outputApk.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new IOException("Cannot create output directory: " + parent.getAbsolutePath());
        }
        if (outputApk.exists() && !outputApk.delete()) {
            throw new IOException("Cannot overwrite output APK: " + outputApkPath);
        }

        KeyMaterial keyMaterial = loadKeyMaterial();
        signWithApkSig(inputApk, outputApk, keyMaterial);
    }

    private static void signWithApkSig(File inputApk, File outputApk, KeyMaterial keyMaterial) throws Exception {
        try {
            Class<?> signerConfigBuilderClass = Class.forName("com.android.apksig.ApkSigner$SignerConfig$Builder");
            Object signerConfigBuilder = signerConfigBuilderClass
                    .getConstructor(String.class, PrivateKey.class, List.class)
                    .newInstance("androlua", keyMaterial.privateKey, Collections.singletonList(keyMaterial.certificate));
            Object signerConfig = signerConfigBuilderClass.getMethod("build").invoke(signerConfigBuilder);

            Class<?> signerBuilderClass = Class.forName("com.android.apksig.ApkSigner$Builder");
            Object signerBuilder = signerBuilderClass
                    .getConstructor(List.class)
                    .newInstance(Collections.singletonList(signerConfig));

            invoke(signerBuilderClass, signerBuilder, "setInputApk", new Class[]{File.class}, inputApk);
            invoke(signerBuilderClass, signerBuilder, "setOutputApk", new Class[]{File.class}, outputApk);
            invoke(signerBuilderClass, signerBuilder, "setV1SigningEnabled", new Class[]{boolean.class}, true);
            invoke(signerBuilderClass, signerBuilder, "setV2SigningEnabled", new Class[]{boolean.class}, true);

            Object apkSigner = signerBuilderClass.getMethod("build").invoke(signerBuilder);
            apkSigner.getClass().getMethod("sign").invoke(apkSigner);
        } catch (InvocationTargetException e) {
            Throwable cause = e.getCause();
            if (cause instanceof Exception) {
                throw (Exception) cause;
            }
            throw new RuntimeException(cause);
        } catch (ClassNotFoundException e) {
            throw new IllegalStateException("ApkSig runtime is unavailable", e);
        }
    }

    private static void invoke(Class<?> owner, Object target, String methodName, Class<?>[] parameterTypes, Object... args)
            throws Exception {
        Method method = owner.getMethod(methodName, parameterTypes);
        method.invoke(target, args);
    }

    private static KeyMaterial loadKeyMaterial() throws Exception {
        LuaApplication app = LuaApplication.getInstance();
        if (app == null) {
            throw new IllegalStateException("LuaApplication is not initialized");
        }
        AssetManager assets = app.getAssets();

        byte[] privateKeyBytes;
        try (InputStream keyInput = assets.open(KEY_ASSET_PATH)) {
            privateKeyBytes = readAllBytes(keyInput);
        }

        X509Certificate certificate;
        try (InputStream certInput = assets.open(CERT_ASSET_PATH)) {
            certificate = (X509Certificate) CertificateFactory.getInstance("X.509").generateCertificate(certInput);
        }

        PrivateKey privateKey = parsePrivateKey(privateKeyBytes, certificate.getPublicKey().getAlgorithm());
        return new KeyMaterial(privateKey, certificate);
    }

    private static PrivateKey parsePrivateKey(byte[] privateKeyBytes, String preferredAlgorithm)
            throws GeneralSecurityException {
        PKCS8EncodedKeySpec keySpec = new PKCS8EncodedKeySpec(privateKeyBytes);
        List<String> algorithms = Arrays.asList(preferredAlgorithm, "RSA", "EC", "DSA");
        GeneralSecurityException lastError = null;
        for (String algorithm : algorithms) {
            if (algorithm == null || algorithm.isEmpty()) {
                continue;
            }
            try {
                return KeyFactory.getInstance(algorithm).generatePrivate(keySpec);
            } catch (GeneralSecurityException e) {
                lastError = e;
            }
        }
        if (lastError != null) {
            throw lastError;
        }
        throw new GeneralSecurityException("No supported private key algorithm found");
    }

    private static byte[] readAllBytes(InputStream inputStream) throws IOException {
        ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
        byte[] buffer = new byte[4096];
        int read;
        while ((read = inputStream.read(buffer)) != -1) {
            outputStream.write(buffer, 0, read);
        }
        return outputStream.toByteArray();
    }

    private static final class KeyMaterial {
        private final PrivateKey privateKey;
        private final X509Certificate certificate;

        private KeyMaterial(PrivateKey privateKey, X509Certificate certificate) {
            this.privateKey = privateKey;
            this.certificate = certificate;
        }
    }
}

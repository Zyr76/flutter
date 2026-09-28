package com.androlua;

public final class ApkSigner {
    private ApkSigner() {
    }

    public static void sign(String inputApkPath, String outputApkPath) throws Exception {
        apksigner.Signer.sign(inputApkPath, outputApkPath);
    }
}

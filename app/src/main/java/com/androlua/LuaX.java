package com.androlua;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;

/**
 * LUAX 加密脚本支持（供打包模块 bin.lua 调用）。
 *
 * <p>加密在 native 侧完成，密钥只存在于 libluajava.so 中，Lua 脚本拿不到。
 * 解密由 luajava.c 的 LloadFile/LloadBuffer 在加载时自动识别文件头完成。
 */
public final class LuaX {

    private LuaX() {
    }

    /** 加密成功返回带 LUAX 头的字节；输入不是合法脚本或内存不足返回 null。 */
    public static native byte[] encrypt(byte[] data);

    /**
     * 加密单个 .lua 文件。
     *
     * @return true 表示已写密文；false 表示跳过（文件含 @cpp 预处理块，加密会绕过预处理）
     */
    public static boolean encryptFile(String src, String dst) throws IOException {
        byte[] data = readAll(src);
        if (containsCppBlock(data)) {
            writeAll(dst, data);
            return false;
        }
        byte[] out = encrypt(data);
        if (out == null) {
            throw new IOException("LUAX 加密失败: " + src);
        }
        writeAll(dst, out);
        return true;
    }

    /** 从 src 读出内容，加密后直接写入 out（打包时塞进 ZipOutputStream 用）。 */
    public static void copyEncrypted(String src, OutputStream out) throws IOException {
        byte[] data = readAll(src);
        if (containsCppBlock(data)) {
            out.write(data);
            return;
        }
        byte[] enc = encrypt(data);
        if (enc == null) {
            throw new IOException("LUAX 加密失败: " + src);
        }
        out.write(enc);
    }

    private static boolean containsCppBlock(byte[] data) {
        byte[] needle = "@cpp".getBytes();
        outer:
        for (int i = 0; i + needle.length <= data.length; i++) {
            for (int j = 0; j < needle.length; j++) {
                if (data[i + j] != needle[j]) {
                    continue outer;
                }
            }
            return true;
        }
        return false;
    }

    private static byte[] readAll(String path) throws IOException {
        File f = new File(path);
        byte[] buf = new byte[(int) f.length()];
        try (FileInputStream in = new FileInputStream(f)) {
            int off = 0;
            while (off < buf.length) {
                int n = in.read(buf, off, buf.length - off);
                if (n < 0) {
                    break;
                }
                off += n;
            }
        }
        return buf;
    }

    private static void writeAll(String path, byte[] data) throws IOException {
        File f = new File(path);
        File parent = f.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new IOException("无法创建目录: " + parent);
        }
        try (FileOutputStream out = new FileOutputStream(f)) {
            out.write(data);
        }
    }
}

package com.androlua;

import com.chaquo.python.PyObject;
import com.chaquo.python.Python;
import com.chaquo.python.android.AndroidPlatform;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.nio.charset.StandardCharsets;

public final class PythonBridge {
    private static final String EXEC_HELPER_SOURCE = """
            import io
            import json
            import sys
            import traceback
            
            def __androlua_exec(code, filename, argv_json):
                globals_dict = {"__name__": "__main__", "__file__": filename}
                old_stdout, old_stderr = sys.stdout, sys.stderr
                old_argv = sys.argv
                out = io.StringIO()
                err = io.StringIO()
                try:
                    sys.argv = json.loads(argv_json)
                    sys.stdout = out
                    sys.stderr = err
                    exec(compile(code, filename, "exec"), globals_dict, globals_dict)
                except Exception:
                    raise RuntimeError(err.getvalue() + traceback.format_exc())
                finally:
                    sys.stdout = old_stdout
                    sys.stderr = old_stderr
                    sys.argv = old_argv
                if "__result__" in globals_dict:
                    return str(globals_dict["__result__"])
                stderr_text = err.getvalue().strip()
                if stderr_text:
                    raise RuntimeError(stderr_text)
                return out.getvalue()
            """;
    private static volatile PyObject executor;

    private PythonBridge() {
    }

    public static String runCode(String code, String[] args) throws Exception {
        if (code == null) {
            throw new IllegalArgumentException("code must not be null");
        }
        return execute(null, code, args);
    }

    public static String runFile(String scriptPath, String[] args) throws Exception {
        if (scriptPath == null) {
            throw new IllegalArgumentException("scriptPath must not be null");
        }
        File file = new File(scriptPath);
        if (!file.isFile()) {
            throw new IllegalArgumentException("Python script not found: " + scriptPath);
        }
        return execute(file, null, args);
    }

    private static String execute(File scriptFile, String code, String[] args) throws Exception {
        ensureInitialized();
        String filename = scriptFile != null ? scriptFile.getAbsolutePath() : "<string>";
        String argvJson = buildArgvJson(filename, args);
        String source = scriptFile != null ? readUtf8(scriptFile) : code;
        PyObject resultObj = executor.call(source, filename, argvJson);
        return resultObj == null ? "" : resultObj.toString();
    }

    private static void ensureInitialized() {
        if (executor != null) {
            return;
        }
        synchronized (PythonBridge.class) {
            if (executor != null) {
                return;
            }

            LuaApplication app = LuaApplication.getInstance();
            if (app == null) {
                throw new IllegalStateException("LuaApplication is not initialized");
            }
            if (!Python.isStarted()) {
                Python.start(new AndroidPlatform(app));
            }

            Python py = Python.getInstance();
            PyObject builtins = py.getBuiltins();
            PyObject mainModule = py.getModule("__main__");
            PyObject mainDict = mainModule.get("__dict__");
            builtins.callAttr("exec", EXEC_HELPER_SOURCE, mainDict, mainDict);
            PyObject execFn = mainModule.get("__androlua_exec");
            if (execFn == null) {
                throw new IllegalStateException("Failed to initialize Python executor");
            }
            executor = execFn;
        }
    }

    private static String buildArgvJson(String filename, String[] args) {
        StringBuilder sb = new StringBuilder();
        sb.append('[');
        appendJsonString(sb, filename);
        if (args != null) {
            for (String arg : args) {
                sb.append(',');
                appendJsonString(sb, arg == null ? "" : arg);
            }
        }
        sb.append(']');
        return sb.toString();
    }

    private static void appendJsonString(StringBuilder sb, String value) {
        sb.append('"');
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            switch (c) {
                case '"':
                    sb.append("\\\"");
                    break;
                case '\\':
                    sb.append("\\\\");
                    break;
                case '\b':
                    sb.append("\\b");
                    break;
                case '\f':
                    sb.append("\\f");
                    break;
                case '\n':
                    sb.append("\\n");
                    break;
                case '\r':
                    sb.append("\\r");
                    break;
                case '\t':
                    sb.append("\\t");
                    break;
                default:
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
            }
        }
        sb.append('"');
    }

    private static String readUtf8(File file) throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        try (FileInputStream in = new FileInputStream(file)) {
            int n;
            while ((n = in.read(buffer)) != -1) {
                out.write(buffer, 0, n);
            }
        }
        return out.toString(StandardCharsets.UTF_8.name());
    }
}

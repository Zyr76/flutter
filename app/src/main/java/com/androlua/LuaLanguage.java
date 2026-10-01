package com.androlua;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

import io.github.rosemoe.sora.lang.EmptyLanguage;
import io.github.rosemoe.sora.lang.analysis.AnalyzeManager;
import io.github.rosemoe.sora.lang.analysis.SimpleAnalyzeManager;
import io.github.rosemoe.sora.lang.styling.MappedSpans;
import io.github.rosemoe.sora.lang.styling.Span;
import io.github.rosemoe.sora.lang.styling.Styles;
import io.github.rosemoe.sora.lang.styling.TextStyle;
import io.github.rosemoe.sora.widget.schemes.EditorColorScheme;

/**
 * SoraEditor（io.github.rosemoe.sora.widget.CodeEditor）的 Lua 语言实现：
 * 自带 Lua 词法分析，提供关键字 / 字符串 / 注释 / 数字 / 运算符的语法高亮。
 * 不依赖任何外部语法文件或原生库，颜色取自编辑器默认配色（EditorColorScheme）。
 *
 * <pre>
 * local ed = CodeEditor(activity)
 * ed.setEditorLanguage(LuaLanguage())
 * </pre>
 */
public class LuaLanguage extends EmptyLanguage {

    private static final Set<String> KEYWORDS = new HashSet<String>(Arrays.asList(
            "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto",
            "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true",
            "until", "while"));

    @NonNull
    @Override
    public AnalyzeManager getAnalyzeManager() {
        return new LuaAnalyzeManager();
    }

    private static final class LuaAnalyzeManager extends SimpleAnalyzeManager<Void> {

        @Override
        protected Styles analyze(StringBuilder text, Delegate<Void> delegate) {
            final int n = text.length();
            // 每行的 (列, 颜色) 列表
            final ArrayList<ArrayList<int[]>> lines = new ArrayList<ArrayList<int[]>>();

            int i = 0, line = 0, col = 0;
            while (i < n) {
                char c = text.charAt(i);

                if (c == '\n') {
                    line++;
                    col = 0;
                    i++;
                    continue;
                }

                // 注释：-- 行注释 / --[==[ 块注释 ]==]
                if (c == '-' && i + 1 < n && text.charAt(i + 1) == '-') {
                    int startLine = line, startCol = col;
                    int[] open = longBracket(text, i + 2);
                    if (open != null) {
                        int closeEnd = longBracketClose(text, open[1], open[0]);
                        if (closeEnd < 0) closeEnd = n;
                        int[] le = {line, col};
                        i = advance(text, i, closeEnd, le);
                        markMultiline(lines, startLine, startCol, le[0], le[1], EditorColorScheme.COMMENT);
                    } else {
                        int end = i;
                        while (end < n && text.charAt(end) != '\n') end++;
                        // 单行注释
                        add(lines, line, col, EditorColorScheme.COMMENT);
                        col += (end - i);
                        add(lines, line, col, EditorColorScheme.TEXT_NORMAL);
                        i = end;
                    }
                    continue;
                }

                // 长字符串 [[ ... ]]
                if (c == '[') {
                    int[] open = longBracket(text, i);
                    if (open != null) {
                        int startLine = line, startCol = col;
                        int closeEnd = longBracketClose(text, open[1], open[0]);
                        if (closeEnd < 0) closeEnd = n;
                        // 先算出结束位置（更新 line/col）
                        int[] le = {line, col};
                        i = advance(text, i, closeEnd, le);
                        markMultiline(lines, startLine, startCol, le[0], le[1], EditorColorScheme.LITERAL);
                        continue;
                    }
                }

                // 短字符串 "..." 或 '...'
                if (c == '"' || c == '\'') {
                    int end = i + 1;
                    while (end < n) {
                        char d = text.charAt(end);
                        if (d == '\\') {
                            end += 2;
                            continue;
                        }
                        if (d == c || d == '\n') {
                            end++;
                            break;
                        }
                        end++;
                    }
                    if (end > n) end = n;
                    add(lines, line, col, EditorColorScheme.LITERAL);
                    col += (end - i);
                    add(lines, line, col, EditorColorScheme.TEXT_NORMAL);
                    i = end;
                    continue;
                }

                // 数字
                if (isDigit(c) || (c == '.' && i + 1 < n && isDigit(text.charAt(i + 1)))) {
                    int end = i;
                    while (end < n && isNumberChar(text.charAt(end))) end++;
                    add(lines, line, col, EditorColorScheme.LITERAL);
                    col += (end - i);
                    add(lines, line, col, EditorColorScheme.TEXT_NORMAL);
                    i = end;
                    continue;
                }

                // 标识符 / 关键字
                if (isIdentStart(c)) {
                    int end = i;
                    while (end < n && isIdentChar(text.charAt(end))) end++;
                    String w = text.substring(i, end);
                    add(lines, line, col, KEYWORDS.contains(w) ? EditorColorScheme.KEYWORD : EditorColorScheme.IDENTIFIER_NAME);
                    col += (end - i);
                    add(lines, line, col, EditorColorScheme.TEXT_NORMAL);
                    i = end;
                    continue;
                }

                // 其它可见字符当作运算符
                if (!Character.isWhitespace(c)) {
                    add(lines, line, col, EditorColorScheme.OPERATOR);
                    add(lines, line, col + 1, EditorColorScheme.TEXT_NORMAL);
                }
                col++;
                i++;
            }

            // 构建 Spans
            MappedSpans.Builder builder = new MappedSpans.Builder(lines.size() + 1);
            for (int ln = 0; ln < lines.size(); ln++) {
                ArrayList<int[]> toks = lines.get(ln);
                if (toks.isEmpty()) {
                    builder.add(ln, Span.obtain(0, TextStyle.makeStyle(EditorColorScheme.TEXT_NORMAL)));
                    continue;
                }
                if (toks.get(0)[0] != 0) {
                    builder.add(ln, Span.obtain(0, TextStyle.makeStyle(EditorColorScheme.TEXT_NORMAL)));
                }
                for (int[] t : toks) {
                    builder.add(ln, Span.obtain(t[0], TextStyle.makeStyle(t[1])));
                }
            }
            if (lines.isEmpty()) {
                builder.add(0, Span.obtain(0, TextStyle.makeStyle(EditorColorScheme.TEXT_NORMAL)));
            }

            Styles styles = new Styles();
            styles.spans = builder.build();
            return styles;
        }

        private static void add(ArrayList<ArrayList<int[]>> lines, int line, int col, int color) {
            while (lines.size() <= line) lines.add(new ArrayList<int[]>());
            lines.get(line).add(new int[]{col, color});
        }

        private static void markMultiline(ArrayList<ArrayList<int[]>> lines, int sLine, int sCol, int eLine, int eCol, int color) {
            add(lines, sLine, sCol, color);
            for (int l = sLine + 1; l <= eLine; l++) add(lines, l, 0, color);
            add(lines, eLine, eCol, EditorColorScheme.TEXT_NORMAL);
        }

        /** 判定 i 处是否是长括号开始 [=*[，返回 {等号数, '['后一位}；否则 null。 */
        private static int[] longBracket(CharSequence s, int i) {
            int n = s.length();
            if (i >= n || s.charAt(i) != '[') return null;
            int j = i + 1, eq = 0;
            while (j < n && s.charAt(j) == '=') {
                eq++;
                j++;
            }
            if (j < n && s.charAt(j) == '[') return new int[]{eq, j + 1};
            return null;
        }

        /** 从 from 起找 ]=*] 结束，返回结束后的下标；找不到返回 -1。 */
        private static int longBracketClose(CharSequence s, int from, int eq) {
            int n = s.length();
            for (int j = from; j < n; j++) {
                if (s.charAt(j) == ']') {
                    int k = j + 1, e = 0;
                    while (k < n && s.charAt(k) == '=') {
                        e++;
                        k++;
                    }
                    if (e == eq && k < n && s.charAt(k) == ']') return k + 1;
                }
            }
            return -1;
        }

        /** 从 from 前进到 end，更新 pos={line,col}，返回 end。 */
        private static int advance(CharSequence s, int from, int end, int[] pos) {
            for (int k = from; k < end && k < s.length(); k++) {
                if (s.charAt(k) == '\n') {
                    pos[0]++;
                    pos[1] = 0;
                } else {
                    pos[1]++;
                }
            }
            return end;
        }

        private static boolean isDigit(char c) {
            return c >= '0' && c <= '9';
        }

        private static boolean isNumberChar(char c) {
            return (c >= '0' && c <= '9') || c == '.' || c == 'x' || c == 'X'
                    || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F') || c == '_';
        }

        private static boolean isIdentStart(char c) {
            return c == '_' || Character.isLetter(c);
        }

        private static boolean isIdentChar(char c) {
            return c == '_' || Character.isLetterOrDigit(c);
        }
    }
}

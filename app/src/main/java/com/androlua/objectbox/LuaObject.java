package com.androlua.objectbox;

import io.objectbox.annotation.Entity;
import io.objectbox.annotation.Id;
import io.objectbox.annotation.Index;

/**
 * 通用实体：一个 space（命名空间）下的 key → value。
 *
 * <p>ObjectBox 的实体必须在编译期由注解处理器生成访问代码，无法在运行时动态建表，
 * 所以这里用一个通用实体承载任意 Lua 数据：space 当“表名”，key 当“键”，
 * value 存 JSON 文本（字符串/数字/布尔/表都能塞进去）。
 */
@Entity
public class LuaObject {
    @Id
    public long id;

    @Index
    public String space;

    @Index
    public String key;

    /** JSON 文本；字符串本身也会被编码成 JSON 字符串。 */
    public String value;

    public long updatedAt;
}

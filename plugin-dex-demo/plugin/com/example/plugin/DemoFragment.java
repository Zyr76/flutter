package com.example.plugin;

import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import androidx.fragment.app.Fragment;

/**
 * 示例插件页面（编译进 plugin.dex，不在宿主 Manifest 注册）。
 *
 * <p>这个类演示三件事：
 * <ol>
 *   <li>继承 <b>androidx.fragment.app.Fragment</b>（必须是 support Fragment，
 *       不能用已废弃的 android.app.Fragment，否则宿主 FragmentManager 认不了它）；</li>
 *   <li>用公开无参构造函数——宿主通过反射 {@code newInstance()} 实例化；</li>
 *   <li>从 {@link #getArguments()} 读取宿主通过 Intent 传进来的参数（字符串/数字/布尔）。</li>
 * </ol>
 *
 * <p>UI 全部用代码搭建（不引用任何 R 资源），因为单文件 dex 里没有 res，
 * 引用 R.xxx 会在运行期找不到资源。插件要带资源请改用 APK 形式并另建 AssetManager。
 */
public class DemoFragment extends Fragment {

    /** 计数器的当前值；用 savedInstanceState 在重建后恢复，演示 Fragment 状态保持。 */
    private int counter;

    @Override
    public View onCreateView(android.view.LayoutInflater inflater,
                             ViewGroup container,
                             Bundle savedInstanceState) {
        // ---- 1. 读取宿主传来的参数 ----
        // 数字用 Number 统一读取：Lua 的数字经 Java 重载可能落成 double，
        // 直接 getInt 会取不到值，用 Number.intValue()/floatValue() 兼容各种数值类型。
        Bundle args = getArguments();
        String msg = args != null ? args.getString("msg", "(未传 msg)") : "(无参数)";
        int count = number(args, "count", 0).intValue();
        float ratio = number(args, "ratio", 0).floatValue();

        // 重建时恢复计数器
        if (savedInstanceState != null) {
            counter = savedInstanceState.getInt("counter", 0);
        }

        int pad = dp(20);

        LinearLayout root = new LinearLayout(requireContext());
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(pad, pad, pad, pad);

        // 标题
        TextView title = new TextView(requireContext());
        title.setText("插件 Fragment 已加载");
        title.setTextSize(20f);
        title.setTextColor(Color.parseColor("#3F51B5"));
        root.addView(title);

        // 宿主传来的字符串参数
        root.addView(label("收到字符串 msg：" + msg));

        // 宿主传来的数字参数
        root.addView(label("收到数字 count：" + count));
        root.addView(label("收到小数 ratio：" + ratio));

        // 交互控件：演示 Fragment 的运行时状态
        final TextView counterView = label("计数器：0");
        Button button = new Button(requireContext());
        button.setText("点我 +1");
        button.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                counter++;
                counterView.setText("计数器：" + counter);
            }
        });

        root.addView(counterView);
        root.addView(button, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        // 外层套 ScrollView，避免内容多时溢出
        ScrollView scroll = new ScrollView(requireContext());
        scroll.addView(root, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        return scroll;
    }

    @Override
    public void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        outState.putInt("counter", counter);
    }

    /** 从 args 取数字，非数字时返回默认值。 */
    private static Number number(Bundle args, String key, double def) {
        Object v = args == null ? null : args.get(key);
        return v instanceof Number ? (Number) v : def;
    }

    /** 快速造一个普通文本行。 */
    private TextView label(String text) {
        TextView tv = new TextView(requireContext());
        tv.setText(text);
        tv.setTextSize(15f);
        tv.setGravity(Gravity.START);
        tv.setPadding(0, dp(8), 0, dp(8));
        return tv;
    }

    private int dp(float v) {
        return (int) (v * getResources().getDisplayMetrics().density + 0.5f);
    }
}

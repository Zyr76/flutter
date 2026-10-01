-- 材料设计.lua（md3.lua 同义）
-- 一次性引入 Google Material 3（MD3）与常用 AndroidX 控件，之后 loadlayout 里直接写类名即可。
--   用法： require "材料设计"   或   require "md3"
--   例：   activity.setContentView(loadlayout{
--             LinearLayout, orientation="vertical",
--             { MaterialButton, text="MD3 按钮" },
--             { TextInputLayout, { TextInputEditText, hint="MD3 输入框" } },
--             { RecyclerView, layout_width="fill", layout_height=0, layout_weight=1 },
--          })

require "import"

-- ---- Google Material（MD3）----
import "com.google.android.material.button.*"
import "com.google.android.material.card.*"
import "com.google.android.material.textfield.*"
import "com.google.android.material.chip.*"
import "com.google.android.material.tabs.*"
import "com.google.android.material.floatingactionbutton.*"
import "com.google.android.material.appbar.*"
import "com.google.android.material.bottomsheet.*"
import "com.google.android.material.snackbar.*"
import "com.google.android.material.dialog.*"
import "com.google.android.material.progressindicator.*"
import "com.google.android.material.switchmaterial.*"
import "com.google.android.material.checkbox.*"
import "com.google.android.material.radiobutton.*"
import "com.google.android.material.slider.*"
import "com.google.android.material.navigation.*"

-- ---- AndroidX 常用控件 ----
import "androidx.recyclerview.widget.*"
import "androidx.viewpager2.widget.*"
import "androidx.swiperefreshlayout.widget.*"
import "androidx.drawerlayout.widget.*"
import "androidx.coordinatorlayout.widget.*"
import "androidx.constraintlayout.widget.*"
import "androidx.appcompat.widget.*"
import "androidx.cardview.widget.*"
import "androidx.core.widget.*"

-- ---- 第三方控件 ----
import "com.google.android.flexbox.*"      -- FlexboxLayout / FlexboxLayoutManager（FlowLayout）
import "io.github.rosemoe.sora.widget.*"   -- SoraEditor CodeEditor

return true

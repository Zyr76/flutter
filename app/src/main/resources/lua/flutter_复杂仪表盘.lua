-- flutter_复杂仪表盘.lua
-- 复杂仪表盘布局：包含图表、列表、卡片、动画、表单等多层嵌套

local hint = "仪表盘就绪，点击任意元素查看事件"

-- ============ 工具函数 ============
local function badge(text, color, bgColor)
  return { Container, padding = { 4, 2, 4, 2 }, radius = 4, color = bgColor,
    { Text, text = text, fontSize = 11, color = color, fontWeight = "bold" } }
end

local function progressBar(value, color, height)
  return { ClipRRect, radius = height / 2,
    { Container, height = height, color = "#E0E0E0",
      { FractionallySizedBox, widthFactor = value,
        { Container, height = height, color = color, radius = height / 2 } } } }
end

local function iconButton(icon, color, onTap)
  return { GestureDetector, onTap = onTap,
    { Container, width = 40, height = 40, radius = 20, color = color .. "20",
      alignment = "center",
      { Icon, icon = icon, color = color, size = 24 } } }
end

-- ============ 可复用组件 ============
local function metricCard(title, value, unit, change, trend)
  local trendColor = trend == "up" and "#4CAF50" or (trend == "down" and "#F44336" or "#757575")
  local trendIcon = trend == "up" and "arrow_upward" or (trend == "down" and "arrow_downward" or "remove")
  
  return { Card, elevation = 2, shadowColor = "#00000015", margin = { 0, 0, 0, 0 },
    { Container, padding = 16,
      { Column, crossAxisAlignment = "start", gap = 8,
        { Text, text = title, fontSize = 13, color = "#757575" },
        { Row, crossAxisAlignment = "end", gap = 4,
          { Text, text = value, fontSize = 28, fontWeight = "bold", color = "#212121" },
          { Text, text = unit, fontSize = 14, color = "#757575", padding = { 0, 0, 0, 4 } } },
        { Row, gap = 4,
          { Icon, icon = trendIcon, color = trendColor, size = 16 },
          { Text, text = change, fontSize = 12, color = trendColor } } } } }
end

local function activityItem(name, time, status, avatar, onTap)
  local statusColors = { ["进行中"] = "#2196F3", ["已完成"] = "#4CAF50", ["待开始"] = "#FF9800" }
  return { InkWell, onTap = onTap,
    { Container, padding = 12, decoration = { borderBottom = { width = 1, color = "#F0F0F0" } },
      { Row, gap = 12,
        { CircleAvatar, radius = 20, color = "#3F51B520",
          { Text, text = avatar, fontSize = 16, color = "#3F51B5" } },
        { Expanded, 
          { Column, crossAxisAlignment = "start", gap = 2,
            { Text, text = name, fontSize = 15, fontWeight = "500", color = "#212121" },
            { Text, text = time, fontSize = 12, color = "#9E9E9E" } } },
        { Container, padding = { 8, 4, 8, 4 }, radius = 12, color = (statusColors[status] or "#757575") .. "20",
          { Text, text = status, fontSize = 12, color = statusColors[status] or "#757575", fontWeight = "500" } } } } }
end

-- ============ 主页面 ============
local function dashboardPage()
  return {
    Scaffold,
    appBar = {
      AppBar, elevation = 0, backgroundColor = "#1A237E",
      leading = { IconButton, icon = "menu", color = "#FFFFFF", onTap = { call = "openDrawer" } },
      title = { Text, text = "智能仪表盘", fontSize = 20, fontWeight = "bold", color = "#FFFFFF" },
      actions = {
        { IconButton, icon = "notifications", color = "#FFFFFF", onTap = { call = "showNotifications" } },
        { IconButton, icon = "more_vert", color = "#FFFFFF", onTap = { call = "showMoreMenu" } }
      }
    },
    drawer = {
      Drawer,
      child = {
        Column,
        { UserAccountsDrawerHeader,
          decoration = { BoxDecoration, color = "#1A237E" },
          accountName = { Text, text = "李四", fontSize = 18, fontWeight = "bold", color = "#FFFFFF" },
          accountEmail = { Text, text = "lisi@example.com", fontSize = 14, color = "#B0BEC5" },
          currentAccountPicture = { CircleAvatar, radius = 30, backgroundColor = "#FFFFFF",
            { Text, text = "李", fontSize = 24, color = "#1A237E" } } },
        { ListTile, leading = "dashboard", title = "仪表盘", onTap = { call = "navigateTo", args = { page = "dashboard" } } },
        { ListTile, leading = "people", title = "团队", onTap = { call = "navigateTo", args = { page = "team" } } },
        { ListTile, leading = "analytics", title = "分析报告", onTap = { call = "navigateTo", args = { page = "analytics" } } },
        { Divider },
        { ListTile, leading = "settings", title = "设置", onTap = { call = "navigateTo", args = { page = "settings" } } },
        { ListTile, leading = "logout", title = "退出登录", onTap = { call = "logout" } }
      }
    },
    body = {
      SingleChildScrollView,
      child = {
        Column, crossAxisAlignment = "start",
        
        -- 顶部渐变背景区域
        { Container, width = "fill", decoration = { gradient = { colors = { "#1A237E", "#3949AB" }, begin = "topLeft", ["end"] = "bottomRight" } },
          padding = { 20, 16, 20, 60 },
          { Column, crossAxisAlignment = "start", gap = 8,
            { Text, text = "欢迎回来，李四", fontSize = 24, fontWeight = "bold", color = "#FFFFFF" },
            { Text, text = "今天有 5 个任务需要处理", fontSize = 14, color = "#C5CAE9" },
            { SizedBox, height = 16 },
            { Row, gap = 12,
              { Expanded, 
                { Container, padding = 16, radius = 16, color = "#FFFFFF20",
                  { Row, gap = 12,
                    { Icon, icon = "timer", color = "#FFFFFF", size = 32 },
                    { Column, crossAxisAlignment = "start",
                      { Text, text = "工作时间", fontSize = 12, color = "#C5CAE9" },
                      { Text, text = "6h 42m", fontSize = 20, fontWeight = "bold", color = "#FFFFFF" } } } } },
              { Expanded,
                { Container, padding = 16, radius = 16, color = "#FFFFFF20",
                  { Row, gap = 12,
                    { Icon, icon = "task_alt", color = "#FFFFFF", size = 32 },
                    { Column, crossAxisAlignment = "start",
                      { Text, text = "完成率", fontSize = 12, color = "#C5CAE9" },
                      { Text, text = "78%", fontSize = 20, fontWeight = "bold", color = "#FFFFFF" } } } } } } } },
        
        -- 指标卡片网格（覆盖在渐变区域上）
        { Transform, translate = { 0, -40 },
          { Padding, padding = { 16, 0, 16, 0 },
            { GridView, crossAxisCount = 2, crossAxisGap = 12, mainAxisGap = 12, physics = "NeverScrollable",
              metricCard("总销售额", "128,456", "元", "+12.5%", "up"),
              metricCard("活跃用户", "3,842", "人", "+8.3%", "up"),
              metricCard("平均响应", "1.2", "秒", "-0.3s", "down"),
              metricCard("转化率", "3.67", "%", "+0.52%", "up") } } },
        
        -- 图表区域
        { Container, padding = { 16, 0, 16, 16 },
          { Card, elevation = 3, shadowColor = "#00000010", radius = 16,
            { Container, padding = 20,
              { Column, crossAxisAlignment = "start", gap = 16,
                { Row, children = {
                  { Text, text = "本周趋势", fontSize = 18, fontWeight = "bold", color = "#212121" },
                  { Spacer },
                  { DropdownButton, value = "周", items = { { value = "日", text = "日" }, { value = "周", text = "周" }, { value = "月", text = "月" } },
                    onChange = { call = "changePeriod", args = { period = "周" } } }
                } },
                -- 模拟柱状图
                { Container, height = 180,
                  { Row, crossAxisAlignment = "end", gap = 8,
                    { Expanded, { Column, crossAxisAlignment = "center", gap = 4,
                      { Container, height = 120, width = 24, radius = 6, color = "#3F51B560",
                        { Container, height = 72, width = 24, radius = 6, color = "#3F51B5" } },
                      { Text, text = "一", fontSize = 11, color = "#757575" } } },
                    { Expanded, { Column, crossAxisAlignment = "center", gap = 4,
                      { Container, height = 140, width = 24, radius = 6, color = "#3F51B560",
                        { Container, height = 98, width = 24, radius = 6, color = "#3F51B5" } },
                      { Text, text = "二", fontSize = 11, color = "#757575" } } },
                    { Expanded, { Column, crossAxisAlignment = "center", gap = 4,
                      { Container, height = 160, width = 24, radius = 6, color = "#3F51B560",
                        { Container, height = 144, width = 24, radius = 6, color = "#FF9800" } },
                      { Text, text = "三", fontSize = 11, color = "#757575" } } },
                    { Expanded, { Column, crossAxisAlignment = "center", gap = 4,
                      { Container, height = 110, width = 24, radius = 6, color = "#3F51B560",
                        { Container, height = 66, width = 24, radius = 6, color = "#3F51B5" } },
                      { Text, text = "四", fontSize = 11, color = "#757575" } } },
                    { Expanded, { Column, crossAxisAlignment = "center", gap = 4,
                      { Container, height = 150, width = 24, radius = 6, color = "#3F51B560",
                        { Container, height = 105, width = 24, radius = 6, color = "#3F51B5" } },
                      { Text, text = "五", fontSize = 11, color = "#757575" } } },
                    { Expanded, { Column, crossAxisAlignment = "center", gap = 4,
                      { Container, height = 90, width = 24, radius = 6, color = "#3F51B560",
                        { Container, height = 45, width = 24, radius = 6, color = "#4CAF50" } },
                      { Text, text = "六", fontSize = 11, color = "#757575" } } },
                    { Expanded, { Column, crossAxisAlignment = "center", gap = 4,
                      { Container, height = 70, width = 24, radius = 6, color = "#3F51B560",
                        { Container, height = 35, width = 24, radius = 6, color = "#4CAF50" } },
                      { Text, text = "日", fontSize = 11, color = "#757575" } } } } },
                { Row, gap = 16, children = {
                  { Row, gap = 4,
                    { Container, width = 8, height = 8, radius = 4, color = "#3F51B5" },
                    { Text, text = "目标", fontSize = 12, color = "#757575" } },
                  { Row, gap = 4,
                    { Container, width = 8, height = 8, radius = 4, color = "#FF9800" },
                    { Text, text = "实际", fontSize = 12, color = "#757575" } },
                  { Row, gap = 4,
                    { Container, width = 8, height = 8, radius = 4, color = "#4CAF50" },
                    { Text, text = "超额", fontSize = 12, color = "#757575" } }
                } } } } } },
        
        -- 快速操作按钮组
        { Padding, padding = { 16, 0, 16, 16 },
          { Column, crossAxisAlignment = "start", gap = 12,
            { Text, text = "快速操作", fontSize = 18, fontWeight = "bold", color = "#212121" },
            { Row, mainAxisAlignment = "spaceAround", gap = 8,
              { Column, gap = 4, children = {
                iconButton("add", "#4CAF50", { call = "quickAction", args = { action = "create" } }),
                { Text, text = "新建", fontSize = 12, color = "#616161" } } },
              { Column, gap = 4, children = {
                iconButton("upload_file", "#2196F3", { call = "quickAction", args = { action = "upload" } }),
                { Text, text = "上传", fontSize = 12, color = "#616161" } } },
              { Column, gap = 4, children = {
                iconButton("share", "#FF9800", { call = "quickAction", args = { action = "share" } }),
                { Text, text = "分享", fontSize = 12, color = "#616161" } } },
              { Column, gap = 4, children = {
                iconButton("print", "#9C27B0", { call = "quickAction", args = { action = "print" } }),
                { Text, text = "打印", fontSize = 12, color = "#616161" } } },
              { Column, gap = 4, children = {
                iconButton("download", "#607D8B", { call = "quickAction", args = { action = "download" } }),
                { Text, text = "下载", fontSize = 12, color = "#616161" } } } } } },
        
        -- 最近活动列表
        { Container, padding = { 16, 0, 16, 16 },
          { Card, elevation = 2, shadowColor = "#00000008", radius = 16,
            { Container, padding = 16,
              { Column, crossAxisAlignment = "start", gap = 12,
                { Row, children = {
                  { Text, text = "最近活动", fontSize = 18, fontWeight = "bold", color = "#212121" },
                  { Spacer },
                  { TextButton, text = "查看全部", onTap = { call = "viewAllActivities" } }
                } },
                activityItem("项目评审会议", "今天 14:00", "进行中", "王", { call = "activityDetail", args = { id = 1 } }),
                activityItem("代码审查 PR#234", "今天 11:30", "已完成", "赵", { call = "activityDetail", args = { id = 2 } }),
                activityItem("产品需求讨论", "今天 09:00", "已完成", "孙", { call = "activityDetail", args = { id = 3 } }),
                activityItem("性能优化方案", "明天 10:00", "待开始", "李", { call = "activityDetail", args = { id = 4 } }) } } } },
        
        -- 多标签页内容
        { DefaultTabController, length = 3,
          { Column, crossAxisAlignment = "start",
            { TabBar, tabs = {
              { Tab, text = "详情" },
              { Tab, text = "日志" },
              { Tab, text = "附件" }
            }, indicatorColor = "#1A237E", labelColor = "#1A237E", unselectedLabelColor = "#9E9E9E" },
            { Container, height = 200,
              { TabBarView,
                { Container, padding = 16,
                  { Column, crossAxisAlignment = "start", gap = 8,
                    { Text, text = "项目详情", fontSize = 16, fontWeight = "bold" },
                    { Row, gap = 48,
                      { Column, crossAxisAlignment = "start", gap = 4,
                        { Text, text = "负责人", fontSize = 12, color = "#757575" },
                        { Text, text = "张三", fontSize = 14, color = "#212121" } },
                      { Column, crossAxisAlignment = "start", gap = 4,
                        { Text, text = "截止日期", fontSize = 12, color = "#757575" },
                        { Text, text = "2026-10-15", fontSize = 14, color = "#212121" } },
                      { Column, crossAxisAlignment = "start", gap = 4,
                        { Text, text = "优先级", fontSize = 12, color = "#757575" },
                        { Text, text = "高", fontSize = 14, color = "#F44336", fontWeight = "bold" } } },
                    { SizedBox, height = 8 },
                    { Text, text = "描述", fontSize = 12, color = "#757575" },
                    { Text, text = "这是一个复杂的跨部门协作项目，涉及前端、后端和设计团队的协同工作。目前处于关键阶段，需要重点关注性能优化部分。", fontSize = 13, color = "#424242" } } },
                { Container, padding = 16,
                  { Column, crossAxisAlignment = "start", gap = 8,
                    { Text, text = "操作日志", fontSize = 16, fontWeight = "bold" },
                    { Row, gap = 8,
                      { Icon, icon = "circle", color = "#4CAF50", size = 8 },
                      { Text, text = "[10:23] 张三 提交了代码审查", fontSize = 13, color = "#424242" } },
                    { Row, gap = 8,
                      { Icon, icon = "circle", color = "#FF9800", size = 8 },
                      { Text, text = "[09:45] 系统 自动备份完成", fontSize = 13, color = "#424242" } },
                    { Row, gap = 8,
                      { Icon, icon = "circle", color = "#2196F3", size = 8 },
                      { Text, text = "[09:12] 李四 更新了任务状态", fontSize = 13, color = "#424242" } } } },
                { Container, padding = 16,
                  { Column, crossAxisAlignment = "start", gap = 12,
                    { Text, text = "附件列表", fontSize = 16, fontWeight = "bold" },
                    { Row, gap = 12,
                      { Container, width = 64, height = 64, radius = 8, color = "#E3F2FD", alignment = "center",
                        { Icon, icon = "description", color = "#1976D2", size = 32 } },
                      { Expanded,
                        { Column, crossAxisAlignment = "start", gap = 2,
                          { Text, text = "需求文档_v3.pdf", fontSize = 14, color = "#212121" },
                          { Text, text = "2.4 MB · 昨天上传", fontSize = 12, color = "#9E9E9E" } } } },
                    { Row, gap = 12,
                      { Container, width = 64, height = 64, radius = 8, color = "#FFF3E0", alignment = "center",
                        { Icon, icon = "image", color = "#F57C00", size = 32 } },
                      { Expanded,
                        { Column, crossAxisAlignment = "start", gap = 2,
                          { Text, text = "UI设计稿.png", fontSize = 14, color = "#212121" },
                          { Text, text = "5.1 MB · 3天前上传", fontSize = 12, color = "#9E9E9E" } } } } } } } } },
        
        -- 表单区域
        { Container, padding = { 16, 0, 16, 96 },  -- 底部留空间给 BottomNavigationBar
          { Card, elevation = 2, shadowColor = "#00000008", radius = 16,
            { Container, padding = 20,
              { Column, crossAxisAlignment = "start", gap = 16,
                { Text, text = "反馈表单", fontSize = 18, fontWeight = "bold", color = "#212121" },
                { TextField, decoration = { labelText = "主题", hintText = "请输入反馈主题", border = "outline" },
                  onChanged = { call = "inputSubject" } },
                { TextField, decoration = { labelText = "详细描述", hintText = "请详细描述您的问题...", border = "outline" },
                  maxLines = 4, onChanged = { call = "inputDescription" } },
                { Row, gap = 12,
                  { Expanded,
                    { DropdownButtonFormField, decoration = { labelText = "分类", border = "outline" },
                      value = "功能建议", items = {
                        { value = "功能建议", text = "功能建议" },
                        { value = "Bug报告", text = "Bug报告" },
                        { value = "用户体验", text = "用户体验" },
                        { value = "其他", text = "其他" }
                      }, onChanged = { call = "selectCategory", args = { category = "功能建议" } } } },
                  { Expanded,
                    { DropdownButtonFormField, decoration = { labelText = "紧急程度", border = "outline" },
                      value = "普通", items = {
                        { value = "低", text = "低" },
                        { value = "普通", text = "普通" },
                        { value = "高", text = "高" },
                        { value = "紧急", text = "紧急" }
                      }, onChanged = { call = "selectUrgency", args = { urgency = "普通" } } } },
                { Row, gap = 8,
                  { Checkbox, value = false, onChanged = { call = "agreeTerms" } },
                  { Text, text = "我已阅读并同意服务条款", fontSize = 13, color = "#616161" } },
                { SizedBox, width = "fill",
                  { ElevatedButton, style = { backgroundColor = "#1A237E", foregroundColor = "#FFFFFF", padding = { 16, 12 } },
                    onPressed = { call = "submitFeedback" },
                    child = { Text, text = "提交反馈", fontSize = 16, fontWeight = "bold" } } } } } } } } },

      },
    },
    bottomNavigationBar = {
      BottomNavigationBar, type = "fixed", selectedItemColor = "#1A237E", unselectedItemColor = "#9E9E9E",
      currentIndex = 0, onTap = { call = "switchTab" },
      items = {
        { BottomNavigationBarItem, icon = "dashboard", label = "首页" },
        { BottomNavigationBarItem, icon = "bar_chart", label = "统计" },
        { BottomNavigationBarItem, icon = "message", label = "消息", badge = { count = 3, color = "#F44336" } },
        { BottomNavigationBarItem, icon = "person", label = "我的" }
      }
    }
  }
end

-- ============ 渲染与事件处理 ============
local function refresh()
  渲染Flutter(dashboardPage())
end

activity.setContentView(渲染Flutter(dashboardPage()))

function onFlutterEvent(e)
  local name = (e and e.name) or "?"
  local data = (e and e.data) or {}
  
  -- 构建事件消息
  local parts = {"事件:", name}
  if data.action then table.insert(parts, "action=" .. tostring(data.action)) end
  if data.value then table.insert(parts, "value=" .. tostring(data.value)) end
  if data.page then table.insert(parts, "page=" .. tostring(data.page)) end
  if data.id then table.insert(parts, "id=" .. tostring(data.id)) end
  
  hint = table.concat(parts, " ")
  
  -- 特殊事件处理
  if name == "inputSubject" or name == "inputDescription" then
    print(name .. ": " .. tostring(data.value))
    return  -- 输入事件不重绘
  end
  
  if name == "submitFeedback" then
    print("提交反馈表单")
    -- 这里可以调用后端API
  end
  
  refresh()
end

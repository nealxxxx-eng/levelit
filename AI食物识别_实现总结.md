# AI 食物识别功能 - 实现总结

> 日期: 2026-03-23
> 版本: v0.4.0
> 状态: 已完成并通过真机测试

---

## 1. 功能概述

为"磨平"App 实现了核心的 AI 食物拍照识别功能：用户拍一张食物/饮料照片，AI 自动识别名称并估算热量，替代了之前从预置库随机选取的 mock 逻辑。

### 用户体验流程
```
拍照 → "AI 正在分析..." (3-6秒) → 显示分析结果页 → 选择运动模式 → 发送到手表
                                         |
                                    识别失败时 → Alert 弹窗 (重试 / 手动选择)
```

---

## 2. 技术选型

### 2.1 AI 模型选型过程

| 候选方案 | 优点 | 缺点 | 结论 |
|---------|------|------|------|
| Claude Vision (Anthropic) | 准确度高 | 价格偏贵 (~$0.05/次) | 排除 |
| GPT-4o (OpenAI) | 成熟稳定 | 中文食物覆盖一般 | 排除 |
| Gemini Flash (Google) | 极便宜 | 中文食物识别弱 | 排除 |
| Core ML 本地模型 | 离线、免费 | 无法估算热量，需维护数据库 | 排除 |
| **Qwen3.5-Plus (阿里通义)** | **中文食物极好、极便宜** | 需翻墙(已解决) | **采用** |

### 2.2 最终选择: Qwen3.5-Plus

- **单次调用成本**: ~0.002 元 (不到 2 厘)
- **1000 次分析成本**: ~2 元
- **中文食物覆盖**: 极好（中国食物训练数据丰富）
- **响应速度**: 3-6 秒（关闭 Thinking 模式后）

### 2.3 API 接入方式: DashScope Coding Plan

- **接口协议**: Anthropic Messages API 兼容格式
- **端点**: `https://coding.dashscope.aliyuncs.com/apps/anthropic/v1/messages`
- **认证**: `x-api-key` Header + DashScope API Key (sk-sp-*** 前缀)
- **选择原因**: 用户已有 Coding Plan 套餐，直接复用

---

## 3. 系统架构

### 3.1 整体链路
```
  iPhone                    Vercel (香港)               DashScope (北京)
+-----------+            +----------------+           +----------------+
| 拍照       |   HTTPS   | Serverless     |   HTTPS   | Qwen3.5-Plus   |
| 压缩512px  | --------> | Function       | --------> | Vision API     |
| Base64编码  |           | (api/analyze)  |           | (Anthropic兼容) |
| POST请求   |  <------  | 解析AI返回     |  <------  | 返回JSON       |
| 解析JSON   |   JSON    | 校验+格式化    |   JSON    |                |
+-----------+            +----------------+           +----------------+
```

### 3.2 为什么需要中转代理

| 直接调用的问题 | 中转代理的解决方案 |
|---------------|-------------------|
| API Key 暴露在客户端 | Key 存在 Vercel 环境变量，不进代码 |
| 切换模型要更新 App | 代理层切换，App 无需更新 |
| 无法限流/计费 | 可在代理层加限流控制 |
| 无法缓存 | 可按图片 hash 缓存结果 |

### 3.3 Vercel 部署优化

| 优化项 | 优化前 | 优化后 |
|--------|--------|--------|
| 部署区域 | 美国东部 (iad1) | **香港 (hkg1)** |
| 网络链路 | iPhone→美国→北京→美国→iPhone | iPhone→香港→北京→香港→iPhone |
| Thinking 模式 | 开启 (生成1000+ tokens) | **关闭** (直出结果) |
| 响应时间 | 15-20秒 (超时) | **3-6 秒** |

---

## 4. 代码实现详解

### 4.1 Vercel 中转代理

**项目位置**: `~/CC/levelit-proxy/`

**文件结构**:
```
levelit-proxy/
+-- api/
|   +-- analyze.js        # Serverless Function (唯一代码文件)
+-- package.json           # 零依赖
+-- vercel.json            # 路由 + 香港区域配置
+-- .vercel/               # Vercel 项目配置 (自动生成)
```

**核心逻辑 (`api/analyze.js`)**:

1. **接收请求**: POST `{"image": "<base64>"}`，校验大小 < 1.5MB
2. **格式处理**: 自动剥离 `data:image/jpeg;base64,` 前缀，提取纯 Base64
3. **调用 DashScope**: Anthropic Messages API 格式，关键参数:
   - `model: "qwen3.5-plus"`
   - `thinking: { type: "disabled" }` — 关闭思考模式
   - `temperature: 0.3` — 低温度确保稳定输出
   - `max_tokens: 200` — 限制输出长度
4. **System Prompt 设计**:
   - 角色: 食物/饮料热量分析专家
   - 输出: 严格 JSON (`foodName`, `foodEmoji`, `estimatedCalories`, `confidence`)
   - 规则: 基于可见份量估算、多食物取总热量、非食物返回 confidence=0
5. **响应解析**:
   - 从 `content[]` 中查找 `type: "text"` 的块（跳过 thinking 块）
   - 处理可能的 markdown 包裹 (` ```json ... ``` `)
   - 校验字段类型和范围
6. **低置信度处理**: `confidence < 0.3` 时附加 warning 字段

**环境变量**:
- `DASHSCOPE_API_KEY`: 存储在 Vercel 环境变量中，仅 production 可见

**部署地址**: `https://levelit-proxy.vercel.app/api/analyze`

---

### 4.2 iOS FoodAnalysisService

**文件**: `LevelIt/Services/FoodAnalysisService.swift`

**职责**: 图片压缩 → Base64 编码 → API 调用 → JSON 解析

**关键设计**:

| 参数 | 值 | 原因 |
|------|-----|------|
| 图片最大尺寸 | 512px | 平衡清晰度和传输大小 |
| JPEG 压缩质量 | 0.7 | ~50-100KB，足够 AI 识别 |
| 请求超时 | 60s | AI 模型推理需要时间 |
| 置信度阈值 | 0.3 | 低于此值判定为非食物 |

**错误类型** (`AnalysisError`):

| 错误 | 场景 | 用户看到 |
|------|------|---------|
| `.imageCompressionFailed` | JPEG 编码失败 | "图片压缩失败" |
| `.networkError(msg)` | 无网络/DNS 失败 | "网络错误: ..." |
| `.serverError(msg)` | HTTP 非 200 / API 错误 | "服务错误: ..." |
| `.notFood` | confidence < 0.3 | "看起来不是食物或饮料" |
| `.timeout` | 超过 60 秒 | "分析超时，请重试" |

**调试日志** (`[FoodAI]` 前缀，Xcode Console 可见):
```
[FoodAI] 图片压缩完成: 45280 字符, 耗时 12.3ms
[FoodAI] 请求发送中... body 45350 bytes, timeout 60.0s
[FoodAI] 响应: HTTP 200, 128 bytes, 耗时 4.2s
[FoodAI] Body: {"foodName":"珍珠奶茶","foodEmoji":"...","estimatedCalories":450,"confidence":0.9}
[FoodAI] 结果: 珍珠奶茶 ... 450kcal confidence=0.9 总耗时=4.3s
```

---

### 4.3 ScanView 改动

**文件**: `LevelIt/Features/Scan/ScanView.swift`

**改动点**:

1. **新增状态**: `@State private var analysisError: String?`
2. **captureAndAnalyze() 重写**:
   - 拍照获取 `UIImage`（之前被丢弃）
   - 调用 `FoodAnalysisService.analyze(image:)`
   - 成功 → 构造 `FoodAnalysisResult` → 导航到分析结果页
   - 失败 → 设置 `analysisError` → 弹出 Alert
   - 拍到的照片数据通过 `imageData` 传递（为后续落盘做准备）
3. **错误处理 Alert**:
   - 标题: "识别失败"
   - 内容: 具体错误信息
   - 按钮: "重试" (重新拍照分析) / "手动选择" (退回手动选择页)

---

## 5. API 接口规格

### 请求
```
POST https://levelit-proxy.vercel.app/api/analyze
Content-Type: application/json

{
  "image": "<base64 编码的 JPEG 图片，无 data URI 前缀>"
}
```

### 成功响应 (200)
```json
{
  "foodName": "珍珠奶茶",
  "foodEmoji": "...",
  "estimatedCalories": 450,
  "confidence": 0.9
}
```

### 低置信度响应 (200)
```json
{
  "foodName": "非食物",
  "foodEmoji": "...",
  "estimatedCalories": 0,
  "confidence": 0.1,
  "warning": "低置信度：照片可能不是食物或饮料"
}
```

### 错误响应 (4xx/5xx)
```json
{
  "error": "错误类型",
  "detail": "详细信息 (仅调试用)"
}
```

---

## 6. 测试记录

### 6.1 自动化测试 (curl)

| 测试 | 输入 | 结果 | 耗时 |
|------|------|------|------|
| 非食物图片 (红色圆形) | 100x100 JPEG | `{foodName: "非食物", confidence: 0}` + warning | 3.1s |
| 简笔画苹果 | 100x100 JPEG | `{foodName: "苹果", calories: 95, confidence: 0.7}` | 3.9s |
| 简笔画咖啡 | 200x200 JPEG | `{foodName: "黑咖啡", calories: 5, confidence: 0.8}` | 3.9s |
| 无效图片 | 截断 Base64 | `{error: "图片格式无法打开"}` | 0.5s |
| 图片太小 (<10px) | 1x1 JPEG | `{error: "图片尺寸不满足要求"}` | 0.3s |

### 6.2 真机测试 (iPhone)

- 拍照后 "AI 正在分析..." 遮罩正常显示
- 分析完成后自动跳转到分析结果页
- 食物识别准确度良好

---

## 7. 遗留和优化方向

### 已知可优化项

| 优化项 | 优先级 | 说明 |
|--------|--------|------|
| 调试日志清理 | P1 | 上线前删除 `[FoodAI]` print 语句 |
| 拍照落盘 | P0 | 照片存入 Documents/FoodImages/，关联到 DebtTask |
| 图片缓存 | P2 | 代理层按图片 hash 缓存，减少重复调用 |
| 本地预判 | P3 | Core ML 二分类判断"是否食物"，拦截非食物图片不调 API |
| 限流保护 | P2 | Vercel 代理加速率限制，防止滥用 |
| 隐私政策 | P0 | 需在 App 隐私政策中声明照片会上传分析 |

---

## 8. 文件清单

| 文件 | 类型 | 位置 |
|------|------|------|
| `api/analyze.js` | 新增 | `~/CC/levelit-proxy/api/` |
| `package.json` | 新增 | `~/CC/levelit-proxy/` |
| `vercel.json` | 新增 | `~/CC/levelit-proxy/` |
| `FoodAnalysisService.swift` | 新增 | `LevelIt/Services/` |
| `ScanView.swift` | 修改 | `LevelIt/Features/Scan/` |
| `CHANGELOG.md` | 修改 | 项目根目录 |

---

## 9. 运维信息

| 项目 | 信息 |
|------|------|
| Vercel 项目 | `nealxxxx-1063s-projects/levelit-proxy` |
| 生产 URL | `https://levelit-proxy.vercel.app` |
| Vercel 管理台 | `https://vercel.com/nealxxxx-1063s-projects/levelit-proxy` |
| 环境变量 | `DASHSCOPE_API_KEY` (仅 production) |
| 部署区域 | 香港 (hkg1) |
| DashScope 模型 | `qwen3.5-plus` |
| DashScope 端点 | `coding.dashscope.aliyuncs.com` (Coding Plan) |
| 重新部署命令 | `cd ~/CC/levelit-proxy && vercel --prod --yes` |

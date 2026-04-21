# App Icon Prompt Pack

适用项目：AI Wealth Ledger / AI 记账鸭

本文件用于直接交给 Midjourney、Figma AI、设计师或其他图像生成流程。

---

## 1. 核心创意方向

目标气质：

- 现代
- 科技感
- 高级
- 清爽
- 带轻微毛玻璃 / 弥散高光
- 明确体现“AI + 记账 + 丰富分类数据”

统一视觉语言：

- 背景品牌渐变：`#6B4DFF -> #4A47D8`
- 主体材质：`Frosted Glass / Soft Glass`
- 点睛元素：`AiSparklesIcon` 的三颗四角星
- 辅助色光晕：`#E91E63`、`#4CAF50`

---

## 2. Midjourney 英文主提示词

```text
Design a premium mobile app icon for an AI-powered personal finance and bookkeeping app. Use a deep futuristic gradient background from #6B4DFF to #4A47D8, with extremely subtle fine-grain noise for material depth. The main subject should be a soft 3D frosted glass object, such as a ledger book, a cute duck, or a stylized letter A, floating above the background. Add a refined AI sparkle symbol made of three four-point stars, one main star and two smaller stars, softly glowing near the center. The subject should be mostly white frosted glass with delicate edge highlights and subtle translucency. Add very faint accent glows in magenta (#E91E63) and emerald green (#4CAF50) near corners or edges to suggest rich categorized data. The icon should feel elegant, modern, intelligent, premium, soft, glossy, slightly futuristic, iOS-quality, high-end productivity tool, no inner border, centered composition, clean silhouette, strong readability at small sizes --ar 1:1 --stylize 250 --v 7
```

---

## 3. Midjourney 变体提示词

### A. Duck 方向

```text
Premium app icon, AI finance assistant, a cute but sophisticated duck made of white frosted glass, floating above a blue-violet gradient background (#6B4DFF to #4A47D8), subtle noise texture, three-star AI sparkle symbol, soft glow, tiny magenta and emerald accent light, elegant, modern, minimal but dimensional, iOS app icon quality, no border, centered composition --ar 1:1 --stylize 250 --v 7
```

### B. Ledger 方向

```text
Premium bookkeeping app icon, a white frosted glass ledger or notebook with subtle 3D depth, floating on a deep blue-violet gradient background (#6B4DFF to #4A47D8), tiny material noise, AI sparkle symbol with one large four-point star and two small stars, soft high-end glow, slight magenta and emerald accent reflections, clean and premium, readable at small size, iOS-quality icon, no border --ar 1:1 --stylize 220 --v 7
```

### C. Letter A 方向

```text
Premium AI productivity app icon, a stylized capital letter A made of white frosted glass, floating on a futuristic blue-violet gradient background (#6B4DFF to #4A47D8), subtle fine grain noise, elegant AI sparkle symbol made of three four-point stars, slight magenta and emerald accent glow, minimal, clean, modern, high-end, iOS-quality app icon, no inner frame, centered composition --ar 1:1 --stylize 220 --v 7
```

---

## 4. 中文设计简报

请围绕以下要求产出图标：

- 背景必须使用品牌渐变：左上 `#6B4DFF`，右下 `#4A47D8`
- 背景增加极轻微噪点，增强实体感
- 主体不要扁平，要做成白色磨砂玻璃 / 软玻璃材质
- 主体可选：账本、鸭子、字母 A，但必须简洁、可识别
- 加入 AI 点睛符号：三颗四角星（大星 + 两颗小星）
- 辅助色只作为极弱光晕出现：洋红 `#E91E63`，翡翠绿 `#4CAF50`
- 不要再加内边框，不要做成按钮或徽章
- 图标需要在小尺寸下仍然清晰
- 整体气质要像高端 iOS 工具类产品，而不是儿童化或廉价拟物

---

## 5. Figma 手工搭建建议

### 背景层

- 创建 1024 x 1024 画板
- 背景填充线性渐变：`#6B4DFF -> #4A47D8`
- 叠加 2% 到 3% 的细噪点纹理

### 主体层

- 白色主体
- 加入：
  - 背景模糊感
  - 轻微透明度
  - 边缘高光
  - 柔和内阴影 / 外阴影

### Sparkles 层

- 使用三颗四角星构图
- 主星略大，两颗小星做陪衬
- 可用白金色或浅暖白
- 外层加极轻 Glow

### 辅助光晕

- 左下或下侧：少量洋红
- 右上或右侧：少量翡翠绿
- 控制极弱，不可喧宾夺主

---

## 6. 产出要求

请至少导出：

- 1024x1024 主图
- 深色桌面预览
- 浅色桌面预览
- 去背景预览图
- 3 个方向版本（Duck / Ledger / A）

---

## 7. 最终上架提醒

用于 iOS App Store 的最终 1024 图标：

- 必须是 RGB
- 必须无透明通道
- 不可带 alpha

否则会触发 Apple 校验失败。

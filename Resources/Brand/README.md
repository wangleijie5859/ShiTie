# 拾贴视觉资源

设计日期：2026-10-17。图标与封面使用内置 imagegen 工具生成，项目运行和构建均无需图片生成服务。

- `AppIcon.png`：1254 × 1254，透明背景的应用图标源文件。
- `Cover.png`：1672 × 941，项目首页横版封面。
- `Screenshot-Light.png`、`Screenshot-Dark.png`：从项目实际 `ContentView` 渲染的浅色、深色界面预览，使用临时数据库与独立命名剪贴板，全部内容为虚构示例，不含用户历史。
- `../AppIcon.icns`：由 `scripts/make-icon.swift` 从源图生成，包含 16、32、64、128、256、512、1024 像素图标，保留透明度。`scripts/build-app.sh` 自动重新生成并打包；Xcode 工程引用同一份 ICNS。

深青色、奶白纸张与少量暖橙夹片组成叠放便签的标识，表达收集和找回复制内容。横版封面使用同一标识与中文文案，应用内“关于拾贴”同步显示应用图标。

## 图标生成提示词

```text
Use case: logo-brand. Asset type: final macOS app icon for a lightweight native local-only clipboard manager named 拾贴. Create one premium, original, extremely clear 1024x1024 icon, centered with ample transparent padding, no words or letters. A deep dark teal rounded-square macOS icon tile with generous corner radius, occupying about 82 percent of the canvas, truly transparent outside the tile. Inside: two off-white rounded paper notes slightly offset diagonally, the front note has a subtly folded bottom-right corner, two short dark teal text bars and a single small warm orange accent tab on its upper edge. The motif should suggest collecting and retrieving copied text, not a checklist. Quiet contemporary Apple-quality product design: crisp geometric silhouette, tactile matte paper, very subtle natural depth, restrained soft shadow, no glossy glass, no excessive gradients, no environment, no presentation mockup, no watermark, no badge, no borders outside tile. Ensure simple readable silhouette at 32 pixels, carefully balanced optical center. Colors: teal #12665D, deep teal #0C443E, warm ivory #FAF7EF, warm orange #E8A16A. Deliver only the actual finished app icon on a transparent background, not an icon sheet.
```

## 封面生成提示词

参考图：`AppIcon.png`。

```text
Use case: logo-brand. Asset type: finished horizontal project cover for 拾贴, a native macOS clipboard manager. Generate a refined wide 16:9 landscape brand cover with meticulous Chinese typography. The attached image is the exact app icon design reference: preserve its identity and colors, no unrelated logos. Warm ivory #FAF7EF matte background, deep dark teal #0C443E typography, tiny warm orange accent. Editorial minimalism, generous intentional negative space. Left half: large beautiful Chinese sans-serif headline exactly "拾贴" on one line, beneath it smaller text exactly "复制过的，随时找回。", then a subtle small descriptor line exactly "原生 macOS 剪贴板管理". One short thin orange dash above the title. Right half: the reference rounded-square dark teal icon, recognizable two overlapping ivory notes with orange clip, at a tasteful large scale, subtle soft shadow, resting in clear uncluttered space. Bottom left small understated text exactly "轻巧 · 清晰 · 本地优先". Crisp readable text, calm functional product character, sophisticated spacing. No browser chrome, no macOS window, no screenshot, no QR code, no extra words, no watermark, no charts, no ornamental gradients. Deliver the complete ready-to-use horizontal cover image only.
```

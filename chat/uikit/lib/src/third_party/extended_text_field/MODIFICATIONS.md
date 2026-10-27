# extended_text_field Modification Record

## Modification Date: 2025.11.12
## Modified By: vinsonswang

### Changes:
- 2025-11-12: Copy source code from version 16.0.2.

### 项目补丁：2026-10-27

- `ExtendedRenderEditable.computeDistanceToActualBaseline` 将对外基线限定在滚动视口内，避免首行图片或视频高于视口时，`InputDecorator` 把整个可滚动区域移出输入框。段落、媒体尺寸和滚动内容保持原值，不通过缩小封面规避空白。

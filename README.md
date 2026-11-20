# draw-china-research-maps

`draw-china-research-maps` 是一个面向中国区域研究的可复现科研制图 skill，用于在 R 中制作省级和地级市（prefecture/city-level）的专题地图、跨年份对比图和变化图。

## 功能范围

- 内置流程支持省级和地级市地图。已有区县几何时，可用同一套规则绘制区县界。
- 支持用户提供的 GeoJSON.CN 1.6.x 边界。源坐标按 GCJ-02 处理，并在投影前转换为 WGS-84。
- 保留行政区代码、历史行政区变更和地图展示代码之间的可审计 crosswalk。
- 使用球面 Albers 等积投影，并保留台湾、香港和澳门的地图覆盖。
- 提供南海诸岛缩略图、十段线、网格北箭头、比例尺和 PDF 字体检查规范。

## 核心制图规范

中国主图使用：

```text
中央经线：105°E
纬度原点：0°
标准纬线：25°N、47°N
```

南海诸岛缩略图使用独立的低纬度 Albers 投影：

```text
中央经线：115°E
纬度原点：0°
标准纬线：7°N、20°N
```

南海附图裁切到 105–127°E、2°N–23°26′N，北界为北回归线。按裁切后的陆地、岛屿和海上断续线确定投影范围。上边框贴住投影后的最北端，左、右、下三边各留较短投影跨度的 2.5%。同组比较图共用范围。主图显示现有画幅内的十段线。

附图上方设等宽的标识栏，外框和共用的横线采用同样粗细的实线。标识栏左侧是「南海诸岛」，右侧是 500 km 比例尺，数字居中贴近尺条上方。主图的 1,000 km 比例尺在附图右侧。导出后检查标识栏接缝、附图边缘以及主图和附图中应显示的海上断续线。

## 出图与论文排版

所有导出图片均禁止内嵌图题、副标题、图注或数据来源说明。交付时提醒用户在论文中自行添加图题和图注。图中保留地理标识、指北针、比例尺和数值图例。

所有格式中的栅格内容，按论文最终插入尺寸计算，有效分辨率不得低于 600 dpi。PDF 等矢量格式保留矢量图元。导出后按目标版面宽度检查图例、比例尺和附图文字。

中文地理标识使用宋体（`SimSun`），英文字母、数值刻度和比例尺单位使用 Times New Roman。PDF 使用 `cairo_pdf()` 导出，并用 `pdffonts` 和 `pdftoppm` 检查字体及版面。SVG 使用 `svglite::svglite()` 导出，并在安装了对应字体的浏览器或矢量编辑器中检查。

陆地内部的省界统一用白色实线，配向东南侧偏移的深色阴影。市界和区县界使用细实线，根据相邻区域的实际填色选择黑线或白线。区县界样式适用于已具备的区县几何。

同一图幅内，陆地国界和南海十段线采用相同的深色线芯和两层淡紫衬带。陆地国界的衬带露在陆地外侧，十段线的衬带只画在外海一侧，两者的可见宽度一致。中国海岸线单独用蓝色细线绘制，包括岛屿的外缘。

## 快速开始

1. Codex 用户从研究项目根目录运行以下命令，将公开版 skill 安装到项目内的 `.agents/skills/draw-china-research-maps`。

   ```powershell
   git clone https://github.com/Pengtao-Lee/draw-china-research-maps-public.git .agents/skills/draw-china-research-maps
   ```

2. 在研究项目根目录运行依赖检查。

   ```powershell
   Rscript .agents/skills/draw-china-research-maps/scripts/check_map_dependencies.R
   ```

3. 在研究项目的 `map_raw/geojson_cn_v1.6.3/` 中放入有权使用的原始 `100000.json`。该文件应包含名为「十段线」的 `MultiLineString` 要素。
4. 将 R 绘图脚本保存在研究项目根目录，并从该目录运行。下面的路径以研究项目根目录为基准。

   ```r
   source(file.path(".agents", "skills", "draw-china-research-maps", "scripts", "china_map_helpers.R"))
   national_path <- file.path("map_raw", "geojson_cn_v1.6.3", "100000.json")
   maritime <- ten_segment_line(national_path)
   ```

5. 按 [`references/map-standard.md`](references/map-standard.md) 完成坐标转换、代码匹配、投影、缩略图布局和导出检查，并用 `Rscript` 执行保存的脚本。

## 仓库结构

```text
SKILL.md                         skill 主说明
agents/openai.yaml               skill 展示信息和默认提示词
references/map-standard.md       边界、投影、布局和导出规范
scripts/check_map_dependencies.R 依赖环境检查
scripts/china_map_helpers.R      边界解析、坐标转换和投影辅助函数
LICENSE                         代码及文档的 MIT 许可证
```

## 必须保留的输出

每张单图和合成对比图都必须导出 PNG、矢量 PDF 和矢量 SVG 三个版本，使用相同的文件基本名和物理尺寸。PNG 和矢量文件中嵌入的栅格内容按论文实际插图尺寸计算，有效分辨率至少为 600 dpi。每次制图还须保存 `map_code_coverage.csv` 和 `map_metadata.csv`。

元数据应记录边界版本、源/目标坐标系、转换方法和容差、投影参数、缩略图范围和边距、两种比例尺、字体、北箭头、十段线来源、分析单元数和展示多边形数。

## 详细规范

请先阅读 [`SKILL.md`](SKILL.md)，再阅读 [`references/map-standard.md`](references/map-standard.md)。原始研究数据和原始边界文件应与中间数据、代码和输出图分开保存，并且不得在制图过程中覆盖原始数据。

## 许可证与数据来源

本仓库的自有代码和文档采用 [MIT 许可证](LICENSE)。边界数据和研究数据由使用者自行提供，适用各自的授权条款。[GeoJSON.CN 中国地图数据集](https://geojson.cn/data/atlas/china) 是已验证格式的参考来源。公开发布成图时，请按实际发布版本核对适用的地图审核和标注要求。

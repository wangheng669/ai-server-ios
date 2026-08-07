# 产业全景 API 契约

产业选择器、规模、历史趋势、产业链、代表企业、产业观察和数据来源全部由服务端维护。iOS 端只负责渲染；请求失败时展示可重试错误状态，不保存业务数据副本。

## 查询接口

`GET /api/v1/industries/panorama`

响应：

```json
{
  "success": true,
  "data": {
    "version": "2026-07-28",
    "industries": [
      {
        "id": "new-energy",
        "title": "新能源汽车",
        "subtitle": "电池 · 整车 · 补能",
        "icon": "car.side.fill",
        "scale": {
          "value": "1,286.6万辆",
          "metric": "新能源汽车销量",
          "period": "2024年",
          "growth": "+35.5% 同比",
          "source": {
            "name": "工业和信息化部",
            "url": "https://www.miit.gov.cn/...",
            "published_at": "2025-01-21"
          }
        },
        "auto_sales": {
          "period": "2024年完整年度",
          "unit": "万辆",
          "source": {
            "name": "中国汽车工业协会",
            "url": "https://www.caam.org.cn/...",
            "published_at": "2025-01-13"
          },
          "monthly": [{
            "period": "2024-12",
            "total_sales": 348.9,
            "nev_sales": 159.6,
            "total_yoy": 10.5,
            "nev_yoy": 34.0,
            "nev_penetration_rate": 45.7
          }]
        },
        "anchors": ["动力电池", "电驱系统", "整车制造", "充换电服务"],
        "chain": [
          {
            "id": "new-energy-upstream",
            "level": "上游",
            "title": "材料与核心零部件",
            "items": ["锂矿", "正极材料", "负极材料"]
          }
        ],
        "companies": [
          {
            "id": "byd",
            "name": "比亚迪",
            "role": "整车与电池",
            "stage_id": "new-energy-midstream",
            "ticker": "002594.SZ"
          }
        ],
        "insights": [
          {"id": "sales", "title": "产销扩张", "detail": "新能源汽车渗透率持续提升。"}
        ],
        "provenance": ["工信部", "国家发展改革委", "公司公开资料"]
      }
    ]
  }
}
```

客户端当前必需字段：

- `data.version`
- `industries[].id`
- `industries[].title`
- `industries[].subtitle`
- `industries[].icon`（SF Symbols 名称）
- `industries[].scale.value`
- `industries[].scale.metric`
- `industries[].scale.period`
- `industries[].scale.source.name`
- `industries[].anchors`
- `industries[].chain`（固定为上游、中游、下游三组）
- `industries[].companies[].id`
- `industries[].companies[].name`
- `industries[].companies[].role`

`history`、`scale.growth`、`source.url`、`source.published_at`、`company.monogram` 和 `company.ticker` 可选。`company.stage_id` 必须引用 `chain[].id`。未知字段必须允许客户端忽略，方便契约向后兼容。

`auto_sales` 仅用于汽车相关产业，按中国汽车工业协会的产销口径保存月度销量。销量单位由 `unit` 明确给出；同比为协会公布值，环比由客户端基于相邻月份计算；新能源渗透率使用当月新能源汽车销量除以汽车总销量。缺少完整、可追溯来源时不得填充品牌或车型排行。

## 服务端存储建议

第一版使用仓库内版本化 JSON 文件作为内容源，而不是立刻增加数据库表。数据量小、更新频率低，代码评审可以直接看到数字、口径和来源变化；接口启动时读取并校验，读取失败则拒绝启动或回退到最后一份合法版本。

建议文件：`config/industry-panorama.json`

当需要后台编辑、定时更新或多人维护时，再迁移到以下三张表：

- `industries`：产业基础信息和展示顺序
- `industry_scale_snapshots`：产业、指标、数值、周期、来源、发布时间
- `industry_chain_groups`：上中下游分组、环节标签和展示顺序
- `industry_companies`：企业、产业、链路环节、角色、证券代码和展示顺序
- `industry_insights`：定性观察、依据和有效期

规模数据必须保留原始字符串和口径，不能只存一个数值。不同产业可能使用销量、产量、营业收入、产值或规上企业数量，不应在服务端伪装成可直接横向比较的统一指标。

## 缓存与更新

- 响应头建议设置 `Cache-Control: public, max-age=3600`
- `ETag` 使用配置文件内容哈希或 `data.version`
- 数据更新时只追加或替换对应产业的规模快照，不修改历史来源
- 客户端使用 HTTP 缓存协商获取最新版本；请求失败时显示可重试错误状态

## 校验规则

- 产业 `id` 唯一，并与 iOS 已知产业 ID 对齐
- 每个产业恰好一个当前规模快照，且 `period`、`metric`、`source.name` 非空
- 企业 `id` 在产业内唯一，展示企业建议 2–6 家
- `source.url` 必须为 HTTPS
- 每个产业必须包含恰好三个产业链分组
- `stage_id` 必须引用该产业的有效链路分组

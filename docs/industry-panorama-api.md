# 产业全景 API 契约

产业规模、数据来源和代表企业由服务端维护，iOS 端通过公开只读接口加载，并保留同结构的内置兜底数据。

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
        "scale": {
          "value": "1,286.6万辆",
          "metric": "新能源汽车销量",
          "period": "2024年",
          "source": {
            "name": "工业和信息化部",
            "url": "https://www.miit.gov.cn/...",
            "published_at": "2025-01-21"
          }
        },
        "companies": [
          {
            "id": "byd",
            "name": "比亚迪",
            "role": "整车与电池",
            "stage_id": "new-energy-2",
            "ticker": "002594.SZ"
          }
        ]
      }
    ]
  }
}
```

客户端当前必需字段：

- `data.version`
- `industries[].id`
- `industries[].scale.value`
- `industries[].scale.metric`
- `industries[].scale.period`
- `industries[].scale.source.name`
- `industries[].companies[].id`
- `industries[].companies[].name`
- `industries[].companies[].role`

`source.url`、`source.published_at`、`company.stage_id` 和 `company.ticker` 可选。未知字段必须允许客户端忽略，方便契约向后兼容。

## 服务端存储建议

第一版使用仓库内版本化 JSON 文件作为内容源，而不是立刻增加数据库表。数据量小、更新频率低，代码评审可以直接看到数字、口径和来源变化；接口启动时读取并校验，读取失败则拒绝启动或回退到最后一份合法版本。

建议文件：`config/industry-panorama.json`

当需要后台编辑、定时更新或多人维护时，再迁移到以下三张表：

- `industries`：产业基础信息和展示顺序
- `industry_scale_snapshots`：产业、指标、数值、周期、来源、发布时间
- `industry_companies`：企业、产业、链路环节、角色、证券代码和展示顺序

规模数据必须保留原始字符串和口径，不能只存一个数值。不同产业可能使用销量、产量、营业收入、产值或规上企业数量，不应在服务端伪装成可直接横向比较的统一指标。

## 缓存与更新

- 响应头建议设置 `Cache-Control: public, max-age=3600`
- `ETag` 使用配置文件内容哈希或 `data.version`
- 数据更新时只追加或替换对应产业的规模快照，不修改历史来源
- 客户端请求失败时继续展示内置兜底，不显示空状态

## 校验规则

- 产业 `id` 唯一，并与 iOS 已知产业 ID 对齐
- 每个产业恰好一个当前规模快照，且 `period`、`metric`、`source.name` 非空
- 企业 `id` 在产业内唯一，展示企业建议 2–6 家
- `source.url` 必须为 HTTPS
- `stage_id` 存在时必须引用该产业的有效链路环节

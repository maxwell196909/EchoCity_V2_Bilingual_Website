# EchoCity MVP

EchoCity is a mission-driven community service platform. This release focuses on one complete service-delivery loop and preserves the permanent five-level architecture defined in `00_Constitution`.

EchoCity 是使命驱动型社区服务平台。本版本优先落地一条完整服务闭环，并遵守 `00_Constitution` 中永久固定的五级纵向架构。

## Current service loop / 当前服务闭环

1. Customer submits a request / 客户提交需求
2. Platform reviews and prepares a quote / 平台审核并报价
3. Customer confirms the quote / 客户确认报价
4. Platform assigns a worker / 平台派工
5. Worker accepts, arrives, and starts / 工人接单、到场、开工
6. Worker submits milestones / 工人提交里程碑
7. Customer performs milestone and final acceptance / 客户进行里程碑与最终验收
8. Settlement and evaluation / 结算与评价

## Main entry points / 主要入口

- `index.html`: unified entrance / 统一入口
- `assets/service-request.html`: customer request / 客户需求发布
- `assets/customer-dashboard.html`: customer area / 客户工作区
- `assets/worker-dashboard.html`: worker area / 工人工作区
- `assets/admin-dashboard.html`: platform management / 平台管理区

## Publishing / 发布

Publish the repository root with GitHub Pages, or open the root folder with VS Code Live Server. Do not open individual HTML files directly with a `file://` address.

使用 GitHub Pages 发布仓库根目录，或在 VS Code 中对根目录使用 Live Server。不要通过 `file://` 地址直接打开单个 HTML 文件。

## Important / 重要

The browser uses a Supabase publishable key. Database security must be enforced with Row Level Security (RLS) policies. Never place a Supabase service-role key in this repository.

浏览器使用 Supabase 可公开密钥，数据库安全必须通过行级安全策略（RLS）实现。不得把 Supabase service-role 密钥放进本仓库。

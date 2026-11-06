# Telegram 自动推送设置说明

## 1. 添加 GitHub Secrets

1. 打开仓库：https://github.com/zfzfboom/us-equity-liquidity-monitor
2. 进入 **Settings** → **Secrets and variables** → **Actions**
3. 点击 **New repository secret**，分别添加以下两个：

| Name | Value |
|------|-------|
| `TELEGRAM_BOT_TOKEN` | 你的 Bot Token（从 @BotFather 获取） |
| `TELEGRAM_CHAT_ID`   | 你的 Chat ID（可以是个人ID或群组ID） |

> 注意：Secret 名称必须完全一致（区分大小写）。

## 2. 工作流说明

- **触发时间**：每个交易日美东时间 16:30（收盘后30分钟）
- **对应 UTC**：21:30 UTC（冬令时 EST）
- **手动触发**：也可以在 Actions 页面手动运行 `Daily Liquidity Summary to Telegram`

## 3. 发送逻辑

1. 如果当天存在 `daily/YYYY-MM-DD.md` 文件 → 自动把该文件内容发送到 Telegram
2. 如果当天还没有填写 → 发送提醒消息，提示你去填写检查清单

## 4. 推荐使用流程

1. 每天下午美股收盘后，尽快填写并提交 `daily/YYYY-MM-DD.md`
2. 16:30 ET 左右，Telegram 会自动收到总结
3. 如果忘记填写，也会收到提醒

## 5. 测试方法

在仓库的 **Actions** 页面，选择 `Daily Liquidity Summary to Telegram`，点击 **Run workflow** 即可手动测试。

# Codex 会话窗口

macOS 本地伴侣应用。将现有 Codex 会话的进度分别放到可拖动、缩放、最小化和置顶的独立窗口里。

## 安装

需要 macOS 14 或更新版本，支持 Apple 芯片和 Intel Mac。先安装并登录兼容的 [ChatGPT 桌面版](https://chatgpt.com/download/)，并运行一次本地 Codex 会话。在 [GitHub Releases](https://github.com/YangPei1993/codex-task-windows/releases) 下载通用压缩包，解压后在 Finder 打开「Codex 会话窗口」。

发布包采用 ad hoc 签名。Gatekeeper 或企业策略可能限制首次打开。查看 [Apple 的应用打开说明](https://support.apple.com/zh-cn/102445)。

## 使用

1. 在看板搜索标题，或按项目筛选。双击会话直接开窗，也可以按住 `⌘` 多选后点「打开所选」。点「打开进行中」批量打开当前筛选范围内的进行中会话。
2. 点「平铺窗口」或按 `⌘2` 排列已打开的窗口。任务窗右上角的图钉可置顶。按 `⌘1` 返回会话看板。
3. 「最新一轮」先展示回复或最新进度，本轮请求和较早的过程进度可以展开。「全部消息」展示最近 30 条文本消息，还可以关闭「跟随最新」。Codex 回复按 Markdown 渲染，点击本地文件链接会在 Finder 中定位。
4. 在任务窗口底部输入文字，点「发送」或按 `⌘ Return`，向当前会话提交消息。审批和终止任务可以点「回 Codex」处理。

## 本地数据和状态

应用以只读模式查询 `CODEX_HOME`（默认 `~/.codex`）下的 `state_5.sqlite` 和 `thread_history_1.sqlite`，每三秒刷新，显示最近 400 个未归档的本地会话及当前开窗的会话。任务窗可查看最近的进度、回复和工具活动类别。消息显示以 Codex 写入本地记录为准。

「已完成」表示最近一轮应答结束。「待确认」表示本地记录仍为进行中，且已经五分钟没有更新。实际运行或审批状态可在原会话确认。关闭任务窗只结束监看，对应会话继续由 Codex 管理。

应用通过随 Codex 桌面版安装的 `codex queue` 命令按会话 UUID 提交文本。「已加入 Codex 队列」表示 CLI 已确认接收，由 Codex 决定何时处理。如果原会话尚未载入，可以点「回 Codex」打开它。提交失败时窗口保留草稿。当前版本支持本机已写入上述数据库的 Codex 会话，需要 macOS 14 或更新版本。[官方发送命令说明](https://learn.chatgpt.com/docs/cli/reference#codex-queue)

## 从源码构建

在安装了 Xcode 的 Mac 上，从仓库根目录运行以下命令。

```bash
./script/build_and_run.sh
./script/build_and_run.sh --package
./script/build_and_run.sh --verify-data
swift test
```

`--package` 生成 `dist/Codex 会话窗口-macOS.zip`。`--verify-data` 检查本地会话列表、消息和链接处理程序，只输出统计信息。可在命令末尾传入项目名验证指定项目。

## 许可证

[MIT](LICENSE)

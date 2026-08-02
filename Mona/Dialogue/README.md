# 台词

一个文件对应一种说话的场合。改完重新构建即可生效。

| 文件 | 什么时候说 |
|---|---|
| `poke-casual.json` | 随手戳一下，有几率随机挑一句 |
| `poke-pestered.json` | 被连点骚扰时的递进，**有序**，从上往下依次说 |
| `stroke-head.json` | 摸他的头 |
| `stroke-belly.json` | 摸他的肚子 |
| `quota-unavailable.json` | 读不到 Codex 用量记录 |
| `quota-exhausted.json` | 本周额度已用完 |
| `quota-plenty.json` | 额度还剩很多 |
| `quota-low.json` | 额度不多了 |

## 格式

```json
{
  "note": "这个文件是干嘛的，随便写",
  "lines": [
    { "message": "喵……喵？", "expression": "smile" }
  ]
}
```

- `message` —— 说的话，换行写 `\n`
- `expression` —— 表情，可用：`regular` `smile` `kirakira` `angry` `sad` `shocked`
- `note` —— 可选，JSON 不支持注释，需要备注就写在这里；`lines` 里的每一句也可以单独写

## 占位符

`quota-*` 里可以用：

- `{used}` —— 已使用百分比
- `{reset}` —— 下次刷新时间

## 加新表情

`expression` 只接受 `PetExpression` 里已有的值，而且每种表情需要三张图
（`<名字>.png` / `<名字>-talk.png` / `<名字>-talk-half.png`，`smile` 的半开口
是 `smile-half`）。少了图，嘴型动画会静默失效——加表情时记得三张一起加。

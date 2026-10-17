# X-HarmonyOS

X（Twitter）的 HarmonyOS NEXT 原生套壳客户端。单页面 ArkWeb 全屏加载 x.com，
伪装 Chrome/Android UA 获得移动版界面，外链域名白名单拦截，断网时显示原生
"连接失败"提示页。**无任何第三方依赖**，全部有效代码不到 200 行。

> [!NOTE]
> 本项目与 X Corp 无任何关系，仅为个人自用工具。X 是 Twitter, Inc. / X Corp.
> 的商标，项目名仅表示"X 的鸿蒙客户端"。使用 X 网页需遵守 X 的服务条款，
> 请勿在本项目基础上添加任何自动化操作。

## 为什么是套壳（而不是原生 App）

X 的协议闭源、没有 Telegram TDLib 那样可复用的客户端核心库；官方 API 免费档
几乎只写不读（读时间线需付费档）。而 x.com 移动版网页本身是全功能产品——
发帖、回复、私信、视频、搜索、多账号俱全。**套壳因此不是妥协，是这类闭源
平台在第三方端的合理终态**，约等于 90% 的原生体验，工期却只有几小时。

## 功能

| 功能 | 实现方式 |
|---|---|
| 全功能 X 网页 | ArkWeb 全屏加载 `https://x.com/home`，`domStorageAccess` 保登录快照 |
| 移动版界面 | `onControllerAttached` 里 `setCustomUserAgent`（官方文档指定的唯一可靠时机） |
| 登录态持久化 | 登录一次长期有效；`EntryAbility.onBackground` 调 `WebCookieManager.saveCookieSync()` 落盘 |
| 外链安全边界 | `onOverrideUrlLoading` 白名单（`x.com` / `twitter.com` / `t.co` / `twimg.com` / `x.nest`），其余域名甩系统浏览器 |
| 断网提示页 | `onErrorReceive`（仅 `isMainFrame()`）触发原生覆盖层 + 重试按钮；`onPageEnd` 自动收回 |
| 物理返回键 | `accessBackward()` / `backward()` 逐级网页后退，退到底退出 |
| 图片上传 | 不接管 `onShowFileSelector`，用 ArkWeb 自带的默认文件选择器 |

## 环境要求

- DevEco Studio 5.0+（带 HarmonyOS 6.0 / API 20 SDK）
- HarmonyOS NEXT 手机（开发者模式 + USB 调试）
- 华为账号（自动签名用，免费）

## 构建运行

```bash
git clone https://github.com/Starchaser-Cyber/X-HarmonyOS.git
# DevEco Studio 打开仓库根目录（build-profile.json5 所在层），等 Sync 完成
```

1. **File → Project Structure → Project → Signing Configs →
   Automatically generate signature**（登录华为账号，自动生成调试证书）。
2. **签名坑（重要）**：自动签名后 hvigor 仍可能只产出 unsigned hap，装机报
   `9568320 no signature file`。修法：项目级 `build-profile.json5` 的 product
   里补一行：

   ```json5
   "products": [
     {
       "name": "default",
       "signingConfig": "default",   // ← 缺的是这行
       ...
     }
   ]
   ```

   注意 `signingConfig` 只能放在 product 或 signingConfigs 定义层；放进
   `buildModeSet` 或 entry 级 `targets` 会报 Schema 校验失败（00303038）。
3. 手机连机，点 Run ▶。

> 本仓库 `build-profile.json5` 的 `signingConfigs` 恒为空数组：签名材料是
> 机器绑定的，请各自生成，不要提交。

## 不想装 DevEco？直接下载 hap 自签安装

[Releases](../../releases) 页提供 **未签名** 的 `entry-default-unsigned.hap`。
鸿蒙不允许安装无签名包，需要你自己用**华为开发者账号**完成签名安装，两条路：

**方式 A：小白调试助手（图形界面，推荐新手）**

第三方工具，本质是把官方签名流程（AGC 申请调试证书 + Profile 绑定你的设备
UDID + 本地签名）封装成了一键操作，**需要登录你自己的华为开发者账号**，
不会绕过任何系统校验。流程：装好工具 → 登录开发者账号 → 选 hap → 安装。

**方式 B：命令行（无额外工具）**

有 DevEco 或 command-line-tools 的机器上，用你自己的调试证书签名后安装：

```bash
hdc shell bm get -udid        # 取手机 UDID，去 AGC 后台把它加进调试 Profile
hdc install entry-default-signed.hap
```

> ⚠️ 提醒：hap 未签名所以任何人都能签，但**请从本仓库 Releases 下载**，
> 不要装来路不明的重签版本——签名的意义在于"这个包谁签的我信谁"，
> 二进制被篡改后再签名你是无法从安装包本身分辨的。信源码，别信二进制。
> （自验方法：下载后用源码自行构建，比较 ets/modules.abc 的 SHA256。）

## 已知限制（设计取舍，非 bug）

1. **无推送通知** —— ArkWeb 不支持 web push，X 网页自身也不推送。
   替代：X 设置里开启邮件通知。
2. **大陆网络不可直达** —— x.com 服务器被墙。不挂代理启动会走断网提示页。
   常规解法：代理 App 切全局/VPN(TUN) 模式，流量对应用透明。
3. **白名单外域名一律外抛** —— 帮助页(help.x.com)在名单内，其余第三方
   链接跳系统浏览器打开。
4. **前置摄像头** —— 默认文件选择器只拉起后置；要前置需自行实现
   `onShowFileSelector`（约 30 行）。
5. **UA 检测风险** —— X 若收紧客户端检测，改 `Index.ets` 里 `X_UA` 常量即可。

## 定制

| 想改什么 | 改哪里 |
|---|---|
| 起始页 | `entry/src/main/ets/pages/Index.ets` → `HOME_URL` |
| UA | 同上 → `X_UA` |
| 放行域名 | 同上 → `ALLOWED_HOSTS` |
| 应用名 | `AppScope/resources/base/element/string.json` 与 `entry/src/main/resources/base/element/string.json` |
| 图标 | `*/resources/base/media/` 下三个 PNG |

换成别的网站：把 `HOME_URL` 换掉、`ALLOWED_HOSTS` 换成对应域名，这个工程
就是任意站点的鸿蒙套壳模板。

## 踩坑记录（给后来者）

| 坑 | 说明 |
|---|---|
| `@Entry` 根节点 | `build()` 根必须是容器组件（`Stack`/`Column` 等），`Web` 不能当根，否则 hvigor 报 10905210。部分离线检查器不查这条，别只信静态检查 |
| UA 设置时机 | `setCustomUserAgent` 只能放 `onControllerAttached`；放 `onLoadIntercept` 概率性失效 |
| 属性名 | 是 `domStorageAccess` / `javaScriptAccess`，没有 `domStorageEnabled` 这个名字 |
| 返回键 | 是 `accessBackward()` / `backward()`，没有 `goBack` |
| UA 里的 "Mobile" | ArkWeb 靠 UA 是否含 "Mobile" 决定启用 meta viewport |
| 主帧/子帧错误 | `onErrorReceive` 子资源也触发，必须 `isMainFrame()` 过滤，否则提示页乱弹 |

## License

GPL-3.0-or-later，见 [LICENSE](LICENSE)。

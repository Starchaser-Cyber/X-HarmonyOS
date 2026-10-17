/**
 * Index.ets —— X（推特）套壳主页面
 *
 * 全部逻辑就四件事：
 *   1. 全屏 ArkWeb 加载 x.com，UA 伪装成 Chrome/Android（onControllerAttached 里设，官方唯一推荐时机）；
 *   2. 外链白名单：非 x/t.co/twimg 域名一律拦截，甩给系统浏览器，不给套壳 App 留后门；
 *   3. 物理返回 = 网页后退，退到底才退出应用；
 *   4. 断网/被墙时原生提示页"连接失败"+ 重试（onErrorReceive 主帧过滤 + onPageEnd 自动收）。
 *
 * 文件上传（发图）不写代码 —— ArkWeb 不接管 onShowFileSelector 时会弹默认选择器。
 * 推送通知不存在 —— 靠 X 自带的邮件通知兜底（见 README-测试.md）。
 *
 * 历史教训：build() 根节点必须是容器（Web 不能当根，hvigor 报 10905210；
 * 本地 ets_checker 不查这条，见 README-测试.md 修订记录 r2）。
 */

import { webview } from '@kit.ArkWeb';
import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'XShell';
const DOMAIN: number = 0x0001;
const HOME_URL: string = 'https://x.com/home';

/**
 * 完整 Chrome/Android UA。
 * 两个硬要求：
 *   - 覆盖掉 ArkWeb/OpenHarmony 指纹，X 按安卓移动版渲染；
 *   - 必须含 "Mobile" 字段 —— ArkWeb 靠它决定是否启用页面 meta viewport。
 */
const X_UA: string = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

/** 留在 WebView 内加载的域名（含各自子域）；其余一律外抛系统浏览器 */
const ALLOWED_HOSTS: Array<string> = ['x.com', 'twitter.com', 't.co', 'twimg.com', 'x.nest'];

@Entry
@Component
struct Index {
  private ctrl: webview.WebviewController = new webview.WebviewController();

  /** 连接失败状态：主帧加载失败置 true，覆盖 Web 白屏 */
  @State loadFailed: boolean = false;
  /** 主帧失败的调试信息（界面小字显示，可为空） */
  @State failReason: string = '';

  build() {
    // 根节点必须是容器组件（ArkTS 硬约束，错误码 10905210）。
    // Stack 透传全屏尺寸，不给 Web 加任何布局，行为等价。
    Stack() {
      Web({ src: HOME_URL, controller: this.ctrl })
        .onControllerAttached(() => {
          // 官方文档明确：setCustomUserAgent 只能放这个回调里，
          // 放 onLoadIntercept 会概率性失效（页面与 UA 不符）。
          try {
            this.ctrl.setCustomUserAgent(X_UA);
          } catch (e) {
            const err = e as BusinessError;
            hilog.warn(DOMAIN, TAG, 'setCustomUserAgent failed: %{public}s', err.message);
          }
        })
        // ── 连接失败检测（r4）──
        // 只认主帧失败：x.com 页面里几十个子资源（图/脚本）报错不弹提示，
        // 否则正常浏览时提示页会乱闪。
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          if (!event.request.isMainFrame()) {
            return;
          }
          this.loadFailed = true;
          try {
            this.failReason = event.error.getErrorInfo();
          } catch (e) {
            this.failReason = '';
          }
        })
        // ── 加载成功自动收提示（r4）──
        // 不留空：重试成功后提示自动消失，不依赖"乐观清除"独自撑着。
        // onPageEnd 对主文档导航才清状态；子页面导航不动它（防误收）。
        .onPageEnd((event: OnPageEndEvent) => {
          if (this.loadFailed) {
            this.loadFailed = false;
            this.failReason = '';
          }
        })
        .javaScriptAccess(true)
        // X 重度依赖 localStorage（登录快照、界面状态），不开会残
        .domStorageAccess(true)
        .onOverrideUrlLoading((request: WebResourceRequest) => {
          const url: string = request.getRequestUrl();
          if (this.isAllowedUrl(url)) {
            return false; // 白名单 → Web 组件正常加载
          }
          this.openExternally(url);
          return true; // true = 中止本次加载（SDK web.d.ts 原文语义）
        })
        .width('100%')
        .height('100%')

      // ═══════════════════════════════════════
      // 连接失败提示覆盖层（与 Web 并列，Z 轴在上）
      // ═══════════════════════════════════════
      if (this.loadFailed) {
        Column() {
          Text('⚠')
            .fontSize(48)
            .fontColor('#666666')
          Text('连接失败，请检查网络设置')
            .fontSize(18)
            .fontColor('#333333')
            .margin({ top: 16 })
          Text(this.failReason)
            .fontSize(12)
            .fontColor('#999999')
            .margin({ top: 8 })
            .maxLines(2)
          Button('重试')
            .onClick(() => {
              // 乐观清除 + 重载；失败会由 onErrorReceive 重新置位，不会漏
              this.loadFailed = false;
              this.failReason = '';
              this.ctrl.refresh();
            })
            .margin({ top: 24 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#FFFFFF')
      }
    }
    .width('100%')
    .height('100%')
  }

  /**
   * host 精确等于白名单域名，或以 .域名 结尾 → 放行。
   * 非 http(s)（mailto:、自定义 scheme 等）→ 拦截外抛。
   */
  private isAllowedUrl(raw: string): boolean {
    const m: RegExpExecArray | null = /^https?:\/\/([^/:?#]+)/i.exec(raw);
    if (m === null || m.length < 2) {
      return false;
    }
    const host: string = m[1].toLowerCase();
    return ALLOWED_HOSTS.some((d: string) => host === d || host.endsWith('.' + d));
  }

  private openExternally(url: string): void {
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const want: Want = { uri: url };
      ctx.startAbility(want).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'openExternally %{public}s failed: %{public}s', url, err.message);
      });
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'openExternally threw: %{public}s', err.message);
    }
  }

  /** 物理返回：网页能后退就后退，退到底才交还系统（退出应用） */
  onBackPress(): boolean {
    try {
      if (this.ctrl.accessBackward()) {
        this.ctrl.backward();
        return true;
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'back failed: %{public}s', err.message);
    }
    return false;
  }
}

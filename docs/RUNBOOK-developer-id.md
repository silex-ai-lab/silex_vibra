# Runbook：为 Vibra 开通 Developer ID 签名与公证（交给 ChatGPT 执行）

日期：2026-11-12。用途：完成 Apple 账号侧的全部准备，产出 GitHub Actions 发版所需的 8 个 secret。
仓库侧的发版 workflow（签名、公证、staple、打包、cask）由 Vibra 的 fleet 计划另行实现，不在本 runbook 内。

## 给 ChatGPT 的执行规则

1. 你负责导航、点击、核对页面文字。以下动作必须停下，让人接管后再继续：
   - 登录 Apple ID、双重认证、付款（USD 99/年）、签署协议。
   - 任何私钥、证书密码、`.p8` 文件内容、`.p12` 文件内容的生成、查看、复制、粘贴。
2. 你不得在对话里复述、记录或要求人粘贴任何密钥、密码或文件内容。只记录「已完成 / 失败 + 页面上的报错原文」。
3. 每一步结束时，按该步的「检查」一栏核对，并把结果写进最后的「交付清单」。
4. 页面与本 runbook 不一致时，以 Apple / GitHub 当前页面为准，记录差异，不要猜。

## 第 0 步：人先做的决定

选一种注册身份，决定证书上显示的名字：

| 选项 | 证书显示 | 前置条件 | 耗时 |
|---|---|---|---|
| A. Organization（推荐，若 Silex 已是法律实体） | `Developer ID Application: <公司法定名称> (<TEAMID>)` | 公司 D-U-N-S 编号、公司官网、有权代表公司签约 | D-U-N-S 查询或申请可能要数天，Apple 审核可能要数天 |
| B. Individual | `Developer ID Application: <个人姓名> (<TEAMID>)` | 个人 Apple ID，开启双重认证 | 通常较快 |

以后从 B 迁到 A 要重新签发证书。

## 第 1 步：加入 Apple Developer Program

1. 打开 https://developer.apple.com/programs/enroll/ ，点 Start Your Enrollment。
2. **人接管**：登录 Apple ID，完成双重认证。
3. 按第 0 步的选择填写实体类型。选 A 时，填 D-U-N-S 编号；没有编号就按页面链接查询或申请。
4. **人接管**：签协议，付款。
5. 等待激活邮件。激活后打开 https://developer.apple.com/account ，在 Membership details 里找到 **Team ID**（10 个字符）。

检查：Membership 页显示 Program 为 Apple Developer Program，状态有效。记录 Team ID（Team ID 不是密钥，可以记录）。

## 第 2 步：生成 Developer ID Application 证书

只能由账号持有人（Account Holder）创建 Developer ID 证书。

1. **人接管**：在要签名的那台 Mac 上生成 CSR。
   - 打开「钥匙串访问」→ 菜单「钥匙串访问」→「证书助理」→「从证书颁发机构请求证书…」。
   - 邮箱填 Apple ID 邮箱，常用名称填 `Vibra Developer ID`，选「存储到磁盘」。得到 `CertificateSigningRequest.certSigningRequest`。
   - 私钥会留在这台 Mac 的登录钥匙串里。
2. 打开 https://developer.apple.com/account/resources/certificates/add 。
3. 选 **Developer ID** 下的 **Developer ID Application**，点 Continue。
4. Profile Type 选 **G2 Sub-CA**（若页面有此选项），上传本步骤第 1 项生成的 CSR，点 Continue。
5. 下载 `developerID_application.cer`，**人接管**：双击导入钥匙串。
6. **人接管**：在「钥匙串访问」→「我的证书」里找到 `Developer ID Application: … (<TEAMID>)`，展开确认下面挂着私钥。右键 →「导出」→ 格式 `.p12`，设一个强密码。
   - 把 `.p12` 和密码存进密码管理器，作为唯一备份。
   - 不要把 `.p12` 放进任何 git 仓库、云笔记或聊天。

检查（人在终端执行，只把输出里的身份名称告诉 ChatGPT，不要贴其他内容）：

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

应出现一行 `Developer ID Application: <名称> (<TEAMID>)`。记录这个完整字符串，它就是 `MACOS_SIGN_IDENTITY`。

注意：不要随手 Revoke 这张证书。吊销后，用它签过名的已发布版本可能被 Gatekeeper 拒绝。

## 第 3 步：生成公证用的 App Store Connect API Key

1. 打开 https://appstoreconnect.apple.com/access/integrations/api 。
2. 首次使用时页面会要求 Request Access，由 Account Holder 同意。
3. 在 **Team Keys** 下点 **+** 生成新 key：Name 填 `vibra-notary`，Access 选 **Developer**。
   - 若之后 `notarytool` 报 401 或 403，回来另建一个权限为 App Manager 的 key，再把旧的吊销。
4. 记录页面上的 **Issuer ID**（UUID）和这把 key 的 **Key ID**（10 个字符）。这两个不是密钥，可以记录。
5. **人接管**：点 Download API Key，得到 `AuthKey_<KEYID>.p8`。**只能下载一次**，立即存进密码管理器。

检查（人在终端执行，只回报是否成功）：

```sh
xcrun notarytool history --key ~/path/AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER_ID>
```

成功时打印空的或已有的提交历史，不报认证错误。

## 第 4 步：把 secret 放进 GitHub（受保护的 environment）

仓库：https://github.com/silex-ai-lab/silex_vibra

1. 打开 Settings → Environments → New environment，名称 `release`。
2. 在 `release` 里设置：
   - Required reviewers：加仓库 owner。
   - Deployment branches and tags：选 Selected branches and tags，添加 tag 规则 `v*`。
3. 在 `release` environment 的 Environment secrets 里添加以下 8 项。**全部由人粘贴**，ChatGPT 只核对名称拼写：

| Secret 名称 | 值从哪来 | 怎么得到 |
|---|---|---|
| `MACOS_CERT_P12_BASE64` | 第 2 步的 `.p12` | `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERT_PASSWORD` | 第 2 步设的 `.p12` 密码 | 密码管理器 |
| `MACOS_KEYCHAIN_PASSWORD` | 新的随机串，仅 CI 临时钥匙串用 | `openssl rand -base64 32 \| pbcopy` |
| `MACOS_SIGN_IDENTITY` | 第 2 步检查输出的完整身份名 | 例：`Developer ID Application: Example Inc (ABCDE12345)` |
| `APPLE_TEAM_ID` | 第 1 步的 Team ID（发版时用来核对签名的 TeamIdentifier） | Membership 页 |
| `NOTARY_KEY_ID` | 第 3 步的 Key ID | App Store Connect |
| `NOTARY_ISSUER_ID` | 第 3 步的 Issuer ID | App Store Connect |
| `NOTARY_KEY_P8_BASE64` | 第 3 步的 `.p8` | `base64 -i AuthKey_<KEYID>.p8 \| pbcopy` |

4. 粘贴完后执行 `pbcopy < /dev/null` 清空剪贴板。

检查：`release` environment 页面列出 8 个 secret 名称，拼写与上表完全一致；保护规则显示 required reviewer 和 `v*` tag 规则。

## 交付清单（ChatGPT 最后回报这一段，不含任何密钥）

```
注册身份：Organization / Individual
Team ID：__________
MACOS_SIGN_IDENTITY：Developer ID Application: __________ (__________)
notarytool history 自检：通过 / 失败（报错原文：…）
API key 权限：Developer / App Manager
GitHub environment `release`：已建，8 个 secret 名称核对一致，保护规则已设
.p12 与 .p8 已存入密码管理器：是 / 否（由人确认）
与本 runbook 不一致之处：…
```

拿到这份清单后，Vibra 的 fleet 会接着实现并验证发版 workflow：hardened runtime 签名（带 Apple Events entitlement，因为终端跳转用 NSAppleScript）、`notarytool submit --wait`、`stapler staple`、上传到 GitHub Release，以及 Homebrew cask。

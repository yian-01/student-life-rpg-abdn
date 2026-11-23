# Student Life RPG V1.1 同步服务

网页版、Windows 和 Android 使用同一账号后台。版本升级后首次打开「账号与同步」，注册或登录。在保存旧数据的安装包上选择「导入本机 V1.0 数据」，再到其他端登录原账号。退出时先同步未上传的改动，再清理当前端的账号缓存。未同步的改动遇到断网或冲突时，应用会保留修改并暂停退出。原有访客记录独立保存。

## 部署

1. 准备一台可运行 Docker Compose 的 Linux 主机，让同步域名指向主机，开放 TCP 80 和 443。
2. 在本目录复制 `.env.example` 为 `.env`。填入真实域名，`SYNC_SIGNUP_CODE` 留空，用户无需邀请码即可注册。只有需要邀请制的独立部署才设置非空邀请码。邮箱用作账号标识，服务目前无需发邮件。
3. 构建或下载网页验收包，把 `build/web/` 下的文件放在 `backend/site/`，确保有 `backend/site/index.html`。只部署 API 时可留空。
4. 运行 `docker compose up -d --build`。通过 `https://你的API域名/healthz` 检查服务。各平台构建时可传入 `--dart-define=CAMPUS_SYNC_URL=https://你的API域名`。Web 未设置时调用当前站点的 `/v1/`；未预配置的安装包可在账号页填写该地址。
5. 定期使用 SQLite 在线备份保存 `sync_data` 中的数据库，或停服后完整备份卷。Compose 停服后保留命名卷。恢复旧数据库后，客户端会在发现云端版本回退时停下并提示人工核对。

服务存储账号的业务数据与票据。每份快照上限为 64 MiB，超限会保留本机数据并提示。HTTPS 保护传输，服务管理员可访问数据库，部署时应限制卷与备份的访问权限。密码在服务端加盐哈希，设备令牌使用平台安全存储。当前没有找回密码或邮箱验证流程。

注册策略由 API 进程的 `SYNC_SIGNUP_CODE` 决定，前端的可选输入框不会关闭服务端邀请制。旧部署若需开放注册，应先备份 `.env` 和 Compose 配置，将 `SYNC_SIGNUP_CODE` 设为空，并将 Compose 中该项改为 `${SYNC_SIGNUP_CODE:-}`，验证配置后仅重建 API 容器以载入新环境。只编辑 `.env` 或重启旧容器不会更新容器环境；保留原项目名、镜像及数据库卷，不执行 `down -v`。已有账号、登录会话、同步快照和注册频率限制均保留。

### 前端与 API 可使用不同来源

网页、Android、Windows 不需要共用一个前端域名。它们连接同一个 API 才能访问同一份账号数据。网页若部署在不同来源，需要在 API 的 `.env` 中设置 `SYNC_ALLOWED_ORIGINS=https://app.example.com,https://preview.example.com`，并为网页构建配置上述 `CAMPUS_SYNC_URL`。仅填写精确来源（协议、主机及非默认端口），不填路径，不支持通配符。HTTP 只允许本机回环测试来源。未列出的跨域网页请求会被拒绝；同源网页无需额外配置。

浏览器通过 CORS 预检发送 `Authorization`、`If-Match`、`If-None-Match`、`X-Upload-Id` 等同步头，并可读取 `ETag`。客户端使用 Bearer Token，网页请求设置 `credentials: omit`，不依赖跨站 Cookie。CORS 只控制网页来源，允许的来源仍需认证；Windows 和 Android 不受浏览器 CORS 限制，也必须提供有效 Token。

凭证由 `flutter_secure_storage` 的各平台实现持久保存；Web 使用浏览器存储和 WebCrypto，必须在 HTTPS 环境使用。浏览器存储可被用户清理，清理后需重新登录从云端恢复。OS 凭证存储和 Android 实机持久化的验收状态见 [V1.1 验收矩阵](../docs/v1.1-reliability.md)。

## 个人空间、好友与私信

密码最少 8 个 Unicode 字符，已有的较长密码仍可使用。公开 ID 是独立生成的稳定 10 位标识，区别于内部账号 ID，用户通过 ID 查找好友，公开资料不包含邮箱、登录凭证或学业财务数据。头像从内置像素头像中选择；昵称、个人称号与简介可编辑。

所有社交接口都要求有效 Bearer Token，跨来源网页仍使用精确 CORS 白名单：

| 接口 | 行为 |
| --- | --- |
| `GET/PUT /v1/profile` | 查看或编辑当前账号资料；不能修改 ID |
| `GET /v1/people?id=公开ID` | 精确查找公开资料 |
| `GET/POST/DELETE /v1/friends` | 好友列表、发送好友申请、移除好友 |
| `GET/POST/DELETE /v1/friend-requests` | 申请列表、接受申请、拒绝或撤回申请 |
| `GET/POST /v1/messages` | 按好友 ID 查询或发送私信；查询可传 `before` 游标 |

只有申请接收方可以接受，成为双向好友后才能收发私信。移除好友后停止收发。私信为纯文本，最多 2000 字符，历史每页最多 50 条；发送携带唯一 `clientId`，重复请求返回同一消息，内容不一致则拒绝。资料、关系与聊天记录保存在服务端新增表中，不写入业务快照，退出和快照恢复不会清空这些表。完整服务器备份必须包含同一 SQLite 数据库；客户端 JSON 备份不包含社交数据。

聊天页面在前台每 4 秒刷新，并在恢复前台时刷新；有手动刷新按钮。首版不包含附件、语音、群聊或系统推送。新增表以 `CREATE TABLE IF NOT EXISTS` 初始化，兼容已有账号和快照；升级时需同时部署 `sync_server.py` 和 `social.py`。

## 开发与验收

在本目录运行 `python3 -m unittest discover -v`，覆盖同步及社交接口。本地开发可运行 `python3 sync_server.py`，Windows Flutter 调试版填 `http://127.0.0.1:8080`。Android 和 Windows 正式验收都使用可访问的 HTTPS 地址。

Windows 可使用 `python -m unittest -v test_sync_server`；原生 HTTP 端到端测试在 `frontend` 中设置 `CAMPUS_SYNC_E2E=1` 后运行 `flutter test test/app/cloud/sync_e2e_test.dart`，可用 `PYTHON` 指定 Python 可执行文件。跨来源浏览器回归由 `.github/workflows/v11-browser-reliability.yml` 运行，测试环境完全独立于正式站点，不发布或部署网站。

- Windows 从 V1.0 升级后，登录并导入含课程、绩点、作业、考试、任务、事件、分类、预算、报销账目与票据的旧数据。
- 在 Android 登录同一个账号，确认各模块与票据均可打开。
- 两台设备离线分别编辑不同记录，联网回到房间后应自动合并。
- 两台设备修改同一条记录或一端删除另一端编辑时，应显示冲突并支持导出两份副本。
- 退出后检查当前端的账号缓存已清理，再用原账号登录并检查云端数据恢复。断网且有未同步修改时退出应被暂缓，联网保存后可重试。
- 在网页与安装包轮流登录原账号。检查学业、日程和账本均可恢复，再用第二个账号确认数据隔离。学校教务嵌入式网页取课表仅支持 Android 和 Windows，网页版可同步已导入的课表。

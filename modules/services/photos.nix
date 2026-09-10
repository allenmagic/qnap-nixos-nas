{ config, pkgs, lib, ... }:

{
  # ===== Photoview 相册服务 =====
  #
  # 选型理由（2026-09）：需求是「浏览照片 + 手机能传上去，不要求实时同步」。
  # 对比过 Immich（Postgres + Redis + Node.js，约 1GB）与 PhotoPrism（内嵌
  # TensorFlow 不可关）：Photoview 是 Go 单二进制 + SQLite，无外部数据库依赖，
  # 资源最省；而本场景用不到 Immich 的三大卖点（手机 App 自动备份 / AI / 实时同步）。
  #
  # 手机→NAS 的通道已存在，无需本服务参与：
  #   - Samba 的 [data] 共享（手机文件管理器直接写入 /srv/data/photos）
  #   - Syncthing（/srv/data/photos/iPhone 已在同步，见其下的 .stfolder）
  services.photoview = {
    enable = true;

    # 照片根目录。注意：该选项**只**用于把目录只读挂进服务沙箱
    # （模块内 ReadOnlyPaths），Photoview 本身没有「照片根目录」环境变量——
    # 扫描路径要在 Web UI 里配置（Settings → Users → 该用户的 Photos path），
    # 存进 SQLite。首次部署后需登录 UI 手动添加 /srv/data/photos。
    mediaPath = "/srv/data/photos";

    # 与其它服务一致：绑定内网地址。
    # ⚠️ 不用模块默认的 4001——那个端口已被 NFSv3 lockd 占用
    # （见 modules/network/default.nix 的 4000/4001 注释）。
    host = "192.168.10.2";
    port = 9080;

    # 默认即 sqlite，无需外部数据库；数据落在 /var/lib/photoview
    database.type = "sqlite";

    settings = {
      # 关掉 RAW 处理：本库没有 RAW 文件（全 png/jpg/mov）。
      # ⚠️ 这只关运行时行为，**不会**把 darktable 移出闭包——它对 photoview
      # 是普通函数参数，nixpkgs 的包无条件把它作为运行时依赖（连同 opencv /
      # poppler / sane-backends / polkit / ghostscript / colord / graphviz 等）。
      # 也就是说首次部署仍需下载这些包（本次 dry-build 显示约 203 MiB）。
      # 若将来想彻底去掉这块体积，可在 flake/module 里 override 掉 darktable。
      disableRawProcessing = true;

      # 其余功能保持开启（模块默认值）：
      #   disableFaceRecognition = false  人脸识别（dlib，已打包在闭包里）
      #   disableVideoEncoding   = false  视频转码（ffmpeg，已打包在闭包里）
      # 这两个的依赖体积同样无法通过开关削减（编译进包），关掉只省运行时 CPU/内存。
      # 若实测 CPU 或内存吃紧，再按需改为 true。
    };
  };
}

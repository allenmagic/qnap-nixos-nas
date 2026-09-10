{ config, pkgs, lib, ... }:

{
  # 相册服务。选 PhotoPrism 而非 Photoview：后者已停更（2024-06 后无发版），
  # 且其 libheif 绑定与 nixpkgs 1.23.1 CGO 不兼容，26.05/unstable 都编不出来。
  services.photoprism = {
    enable = true;
    originalsPath = "/srv/data/photos";
    address = "192.168.10.2";
    port = 2342;
    storagePath = "/var/lib/photoprism";

    settings = {
      # 模块以 DynamicUser 运行，写不进 nas:nas 的原图目录（755/664）。
      # 只读模式下元数据存 SQLite，原图不被触碰。
      PHOTOPRISM_READONLY = "true";

      # 待观察后再收敛的重项：
      #   闭包约 5 GiB = libtensorflow(CGO 编译期链接，配置去不掉) + darktable
      #   + rawtherapee + ffmpeg×3 + imagemagick + vips。本库无 RAW 文件，
      #   两个 RAW 处理器属纯冗余，需要时可 override 掉。
    };
  };
}

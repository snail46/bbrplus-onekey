# bbrplus-onekey
Linux 一键系统调优与 BBRplus 内核自动开启脚本


方案 1：使用 wget 一键执行（最常用，推荐）

```bash

wget -O bbrplus_optimize.sh "https://raw.githubusercontent.com/snail46/bbrplus-onekey/refs/heads/main/bbrplus_optimize.sh" && chmod +x bbrplus_optimize.sh && ./bbrplus_optimize.sh>```


方案 2：使用 curl 管道一键执行（不留本地文件）

```bash
bash <(curl -sL "https://raw.githubusercontent.com/您的用户名/仓库名/refs/heads/main/bbrplus_optimize.sh")```

# certbot证书自动续期脚本
by coffeesw

注意项目不要放在root目录下，否则nginx没有权限读取其中的文件，或者使用
```bash
sudo chmod -R o+x /root #给整个目录权限
sudo chmod -R o+rx /root/autossl/www/web.coffeesw.top #给其中的某个目录权限
```
sed -i "s|DOMAIN_PLACEHOLDER|$DOMAIN|g" /usr/local/bin/menu
chmod +x /usr/local/bin/menu
cp /usr/local/bin/menu /usr/bin/menu
cp /usr/local/bin/menu /usr/bin/Menu

# LET'S ENCRYPT RENEWAL HOOK (solo si se usó Let's Encrypt)
if [ "$USE_LETSENCRYPT" = true ]; then
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    cat <<'EOF_RENEW' > /etc/letsencrypt/renewal-hooks/deploy/hex-tunnel.sh
#!/bin/bash
set -e
for domain in $RENEWED_DOMAINS; do
    cp /etc/letsencrypt/live/$domain/fullchain.pem /etc/xray/xray.crt
    cp /etc/letsencrypt/live/$domain/privkey.pem /etc/xray/xray.key
    cat /etc/letsencrypt/live/$domain/privkey.pem /etc/letsencrypt/live/$domain/fullchain.pem > /etc/stunnel/stunnel.pem
    chmod 600 /etc/stunnel/stunnel.pem /etc/xray/xray.key
    chmod 644 /etc/xray/xray.crt
    systemctl restart xray stunnel4
    break
done
EOF_RENEW
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/hex-tunnel.sh
    echo "0 3 * * * root certbot renew --quiet --deploy-hook /etc/letsencrypt/renewal-hooks/deploy/hex-tunnel.sh" > /etc/cron.d/certbot-renew
fi

# Finishing
chown -R www-data:www-data /home/vps/public_html
clear
figlet Hex Auto Script By JotchuaDevz -c | lolcat
echo "       ¡Instalación Completa! El sistema necesita reiniciarse para aplicar todos los cambios! "
history -c; rm /root/full.sh 2>/dev/null || true
if [[ "$HEXTUNNEL_NO_REBOOT" == "1" ]]; then
  echo "Reinicio automático omitido (--no-reboot / HEXTUNNEL_NO_REBOOT=1)."
else
  echo "           ¡El servidor se reiniciará en 10 segundos! "
  sleep 10
  reboot
fi